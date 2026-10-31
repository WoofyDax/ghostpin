import Foundation
import CoreLocation
import IDevice

/// Native DVT location client built on the `idevice` Rust library.
/// Flow (iOS 17+): TCP provider -> lockdown -> CoreDeviceProxy -> software
/// tunnel -> RSD handshake -> DVT remote server -> LocationSimulation.
/// All FFI handles are not thread-safe, so every call runs on one serial queue.
final class IDeviceLocationClient: DeviceLocationClient {
    private let queue = DispatchQueue(label: "ghostpin.idevice")
    private var adapter: OpaquePointer?
    private var handshake: OpaquePointer?
    private var server: OpaquePointer?
    private var sim: OpaquePointer?
    private var key: (Data, String)?

    init() {
        let log = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("idevice.log").path
        var buf = Array(log.utf8CString)
        _ = idevice_init_logger(Debug, Debug, &buf)
    }

    /// Raw lockdownd probe (QueryType) to tell "unreachable" from "protocol/pairing" failures.
    private func probe(host: String) -> String {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return "probe: no socket" }
        defer { close(fd) }
        var tv = timeval(tv_sec: 4, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var sa = sockaddr_in()
        sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); sa.sin_family = sa_family_t(AF_INET)
        sa.sin_port = UInt16(62078).bigEndian
        inet_pton(AF_INET, host, &sa.sin_addr)
        let rc = withUnsafePointer(to: &sa) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        if rc != 0 { return "probe: TCP \(host):62078 connect failed errno \(errno)" }
        let body = Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>Label</key><string>GhostPin</string><key>Request</key><string>QueryType</string></dict></plist>".utf8)
        var len = UInt32(body.count).bigEndian
        var out = Data(bytes: &len, count: 4); out.append(body)
        let w = out.withUnsafeBytes { send(fd, $0.baseAddress, out.count, 0) }
        if w < 0 { return "probe: TCP ok but send failed errno \(errno)" }
        var hdr = [UInt8](repeating: 0, count: 4)
        let r = recv(fd, &hdr, 4, 0)
        if r <= 0 { return "probe: TCP ok, lockdownd closed without reply (r=\(r) errno \(errno))" }
        var resp = [UInt8](repeating: 0, count: 512)
        let n = recv(fd, &resp, 512, 0)
        return "probe: lockdownd replied: " + String(decoding: resp.prefix(max(0, n)), as: UTF8.self)
    }

    struct IDeviceError: LocalizedError {
        let step: String, message: String
        var errorDescription: String? { "\(step) failed: \(message)" }
    }

    private func check(_ err: UnsafeMutablePointer<IdeviceFfiError>?, _ step: String) throws {
        guard let err else { return }
        let msg = err.pointee.message.map { String(cString: $0) } ?? "code \(err.pointee.code)"
        idevice_error_free(err)
        throw IDeviceError(step: step, message: msg)
    }

    private func onQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async { cont.resume(with: Result { try work() }) }
        }
    }

    private func teardown() {
        if let sim { location_simulation_free(sim) }
        if let server { remote_server_free(server) }
        if let handshake { rsd_handshake_free(handshake) }
        if let adapter { adapter_free(adapter) }
        sim = nil; server = nil; handshake = nil; adapter = nil; key = nil
    }

    static var rpPairingPath: String {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("rppairing.plist").path
    }

    /// iOS 26.4+ path: RemotePairing over the LocalDevVPN loopback (10.7.0.1:49152).
    private func connectRemotePairing(host: String) throws {
        var rp: OpaquePointer?
        if FileManager.default.fileExists(atPath: Self.rpPairingPath) {
            try check(rp_pairing_file_read(Self.rpPairingPath, &rp), "RP pairing file")
        } else {
            try check(rp_pairing_file_generate("GhostPin", &rp), "RP pairing generate")
        }
        defer { rp_pairing_file_free(rp) }

        var sa = sockaddr_in()
        sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sa.sin_family = sa_family_t(AF_INET)
        sa.sin_port = UInt16(49152).bigEndian
        guard inet_pton(AF_INET, host, &sa.sin_addr) == 1 else {
            throw IDeviceError(step: "Address", message: "bad host \(host)")
        }
        try withUnsafePointer(to: &sa) { p in
            try p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try check(tunnel_create_rppairing($0, socklen_t(MemoryLayout<sockaddr_in>.size), "GhostPin",
                                                  rp, nil, nil, &adapter, &handshake), "RemotePairing")
            }
        }
        _ = rp_pairing_file_write(rp, Self.rpPairingPath)   // persist (pair-setup updates it in place)
        try check(remote_server_connect_rsd(adapter, handshake, &server), "DVT server")
        try check(location_simulation_new(server, &sim), "Location service")
    }

    func connect(pairingFile: Data, host: String) async throws {
        try await onQueue { [self] in
            if sim != nil, let k = key, k.0 == pairingFile, k.1 == host { return }
            teardown()

            var rpError = ""
            do { try connectRemotePairing(host: host); key = (pairingFile, host); return }
            catch { rpError = error.localizedDescription; teardown() }
            guard !pairingFile.isEmpty else {
                throw IDeviceError(step: "Connect", message: rpError)
            }
            do { try connectLockdown(pairingFile: pairingFile, host: host) }
            catch let e as IDeviceError {
                throw IDeviceError(step: e.step, message: e.message + " || remote pairing: " + rpError)
            }
        }
    }

    private func connectLockdown(pairingFile: Data, host: String) throws {
        do {

            var pf: OpaquePointer?
            try pairingFile.withUnsafeBytes { raw in
                try check(idevice_pairing_file_from_bytes(raw.bindMemory(to: UInt8.self).baseAddress,
                                                          UInt(raw.count), &pf), "Pairing file")
            }

            var sa = sockaddr_in()
            sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            sa.sin_family = sa_family_t(AF_INET)
            sa.sin_port = UInt16(62078).bigEndian
            guard inet_pton(AF_INET, host, &sa.sin_addr) == 1 else {
                throw IDeviceError(step: "Address", message: "bad host \(host)")
            }

            var provider: OpaquePointer?
            try withUnsafePointer(to: &sa) { p in
                try p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    try check(idevice_tcp_provider_new($0, pf, "GhostPin", &provider), "Provider")
                }
            }
            defer { idevice_provider_free(provider) }

            var proxy: OpaquePointer?
            do { try check(core_device_proxy_connect(provider, &proxy), "Connect (is LocalDevVPN on?)") }
            catch let e as IDeviceError {
                throw IDeviceError(step: e.step, message: e.message + " | " + probe(host: host))
            }
            var rsdPort: UInt16 = 0
            try check(core_device_proxy_get_server_rsd_port(proxy, &rsdPort), "RSD port")
            try check(core_device_proxy_create_tcp_adapter(proxy, &adapter), "Tunnel")

            var stream: OpaquePointer?
            try check(adapter_connect(adapter, rsdPort, &stream), "RSD socket")
            try check(rsd_handshake_new(stream, &handshake), "RSD handshake")
            try check(remote_server_connect_rsd(adapter, handshake, &server), "DVT server")
            try check(location_simulation_new(server, &sim), "Location service")
            key = (pairingFile, host)
        }
    }

    func setLocation(_ c: CLLocationCoordinate2D) async throws {
        try await onQueue { [self] in
            guard let sim else { throw IDeviceError(step: "Set", message: "not connected") }
            do { try check(location_simulation_set(sim, c.latitude, c.longitude), "Set location") }
            catch { teardown(); throw error }
        }
    }

    func clearLocation() async throws {
        try await onQueue { [self] in
            guard let sim else { return }
            try check(location_simulation_clear(sim), "Clear location")
        }
    }
}
