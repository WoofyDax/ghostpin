import SwiftUI
import MapKit
import Darwin
import NetworkExtension

enum Pace: String, CaseIterable, Identifiable {
    case walk = "Walk", bike = "Bike", drive = "Drive"
    var id: String { rawValue }
    var metersPerSecond: Double { switch self { case .walk: 1.4; case .bike: 5; case .drive: 14 } }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selected: CLLocationCoordinate2D?
    @Published var selectedName = ""
    @Published var waypoints: [CLLocationCoordinate2D] = []
    @Published var pace: Pace = .walk
    @Published var loop = false
    @Published var camera: MapCameraPosition = .automatic
    @Published var isSpoofing = false
    @Published var spoofName = ""
    @Published var busy = false
    @Published var error: String?
    @Published var errorDetails: String?
    @Published var vpnOn = false
    @Published var tunnelStatus: NEVPNStatus = .invalid
    @Published var tunnelError: String?
    @Published var pairingReady = false
    @Published var showHelp = false
    @Published var showRoute = false
    @AppStorage("seenHelp") private var seenHelp = false

    private let backend = OnDeviceBackend()
    private let tunnel = TunnelManager()
    private var timer: Timer?

    var statusText: String {
        if isSpoofing { return spoofName.isEmpty ? "Spoofing is on" : "Spoofing: \(spoofName)" }
        if !pairingReady { return "Setup needed - tap ? for help" }
        if tunnelStatus == .connecting || tunnelStatus == .reasserting { return "Turning on GhostPin's private tunnel..." }
        if !vpnOn { return tunnelError ?? "Tunnel is off - tap ? for help" }
        return "Ready"
    }
    var statusColor: Color {
        if isSpoofing { return .green }
        return (pairingReady && vpnOn) ? .blue : .orange
    }

    init() {
        tunnel.onChange = { [weak self] st in self?.tunnelStatus = st; self?.refreshSetup() }
        refreshSetup()
        startTunnel()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshSetup() }
        }
        if !seenHelp || !pairingReady { showHelp = true; seenHelp = true }
    }

    // MARK: setup checks
    static var docsPairing: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("pairing.plist")
    }

    func refreshSetup() {
        pairingReady = FileManager.default.fileExists(atPath: IDeviceLocationClient.rpPairingPath)
        vpnOn = tunnelStatus == .connected || Self.localDevVPNActive()
    }

    /// Turns on GhostPin's own tunnel. iOS asks permission the first time.
    func startTunnel() {
        Task {
            do { try await tunnel.ensureRunning(); tunnelError = nil }
            catch { tunnelError = "Tunnel couldn't start: \(error.localizedDescription)" }
            refreshSetup()
        }
    }

    /// LocalDevVPN gives the phone a 10.7.x.x address on a utun interface.
    static func localDevVPNActive() -> Bool {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return false }
        defer { freeifaddrs(head) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let i = p {
            if let a = i.pointee.ifa_addr, a.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(a, socklen_t(a.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                if String(cString: host).hasPrefix("10.7.") { return true }
            }
            p = i.pointee.ifa_next
        }
        return false
    }

    func importPairing(_ data: Data) {
        // RemotePairing files contain a public_key; anything else is treated as a classic pairing file.
        if let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           dict["public_key"] != nil {
            try? data.write(to: URL(fileURLWithPath: IDeviceLocationClient.rpPairingPath), options: .completeFileProtection)
        } else {
            try? data.write(to: URL(fileURLWithPath: IDeviceLocationClient.rpPairingPath + ".lockdown"))
        }
        refreshSetup()
    }

    // MARK: actions
    private func run(_ op: @escaping (SpoofBackend) async throws -> Void, done: (() -> Void)? = nil) {
        busy = true
        Task {
            defer { busy = false }
            do { try await op(backend); error = nil; done?() }
            catch {
                let raw = error.localizedDescription
                self.errorDetails = raw
                self.error = Self.friendly(raw)
            }
        }
    }

    static func friendly(_ raw: String) -> String {
        let r = raw.lowercased()
        if r.contains("refused") || r.contains("reset") || r.contains("broken pipe") || r.contains("socket io") {
            return "Couldn't reach your iPhone's location service.\n\n1. Wait a few seconds for GhostPin's tunnel to turn on (it asks permission the first time).\n2. Using only cellular? Tap ? and follow the \"No Wi-Fi\" steps."
        }
        if r.contains("rp pairing") || r.contains("pairing") {
            return "GhostPin isn't paired with this iPhone yet. Run the installer on your Mac again (see the guide), then reopen GhostPin."
        }
        return "Something went wrong. Tap Details for more info."
    }

    func spoof() {
        guard let c = selected else { return }
        let name = selectedName.isEmpty ? String(format: "%.4f, %.4f", c.latitude, c.longitude) : selectedName
        run({ [self] b in try await tunnel.ensureRunning(); try await b.teleport(to: c) }, done: { [weak self] in
            self?.isSpoofing = true; self?.spoofName = name
        })
    }
    func addWaypoint() { if let c = selected { waypoints.append(c) } }
    func startRoute() {
        let w = waypoints, s = pace.metersPerSecond, l = loop
        run({ [self] b in try await tunnel.ensureRunning(); try await b.walk(w, speed: s, loop: l) }, done: { [weak self] in
            self?.isSpoofing = true; self?.spoofName = "\(self?.pace.rawValue ?? "Walk") route"; self?.showRoute = false
        })
    }
    func stopSpoofing() {
        waypoints = []
        run({ try await $0.clear() }, done: { [weak self] in self?.isSpoofing = false; self?.spoofName = "" })
    }

    func search(_ q: String) async {
        let r = MKLocalSearch.Request(); r.naturalLanguageQuery = q
        if let item = try? await MKLocalSearch(request: r).start().mapItems.first {
            selected = item.placemark.coordinate
            selectedName = item.name ?? q
            camera = .region(MKCoordinateRegion(center: item.placemark.coordinate,
                                                latitudinalMeters: 2000, longitudinalMeters: 2000))
        }
    }
}
