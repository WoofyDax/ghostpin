import SwiftUI
import MapKit
import Network

enum Mode: String, CaseIterable, Identifiable {
    case remote = "Remote (via Mac)", onDevice = "On-device"
    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    @AppStorage("mode") var modeRaw = Mode.remote.rawValue
    @AppStorage("relayURL") var relayURL = ""
    @AppStorage("relayToken") var relayToken = ""
    @Published var selected: CLLocationCoordinate2D?
    @Published var waypoints: [CLLocationCoordinate2D] = []
    @Published var speed = 1.4
    @Published var loop = false
    @Published var statusText = "Not connected"
    @Published var error: String?
    @Published var pairing: Data? { didSet { Self.savePairing(pairing) } }
    private var onDevice: OnDeviceBackend?
    private var onDevicePairing: Data?

    private static var pairingURL: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("pairing.plist")
    }
    private static func savePairing(_ d: Data?) {
        if let d { try? d.write(to: pairingURL, options: .completeFileProtection) }
        else { try? FileManager.default.removeItem(at: pairingURL) }
    }
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            let local = path.availableInterfaces.contains { $0.type == .wifi || $0.type == .wiredEthernet }
            Task { @MainActor in self?.noLocalNetwork = !local }
        }
        monitor.start(queue: DispatchQueue(label: "ghostpin.path"))
    }

    init() {
        startMonitoring()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pairing.plist")
        if let d = try? Data(contentsOf: docs) {          // dropped in via Files / devicectl
            pairing = d; try? FileManager.default.removeItem(at: docs)
        } else { pairing = try? Data(contentsOf: Self.pairingURL) }
    }
    @Published var camera: MapCameraPosition = .automatic
    /// True when the phone has no Wi-Fi/hotspot-type interface; on-device mode needs one (see docs).
    @Published var noLocalNetwork = false
    private let monitor = NWPathMonitor()

    var mode: Mode { Mode(rawValue: modeRaw) ?? .remote }

    func backend() throws -> SpoofBackend {
        switch mode {
        case .remote: return try RemoteBackend(urlString: relayURL, token: relayToken)
        case .onDevice:
            guard let pairing else { throw SpoofError.unsupported("Import a pairing file in Settings.") }
            if onDevice == nil || onDevicePairing != pairing {
                onDevice = OnDeviceBackend(pairingFile: pairing); onDevicePairing = pairing
            }
            return onDevice!
        }
    }

    func run(_ op: @escaping (SpoofBackend) async throws -> Void) {
        Task {
            do { try await op(try backend()); error = nil; await refresh() }
            catch { self.error = error.localizedDescription }
        }
    }

    func refresh() async {
        guard let s = try? await backend().status() else { statusText = "Relay unreachable"; return }
        statusText = (s.connected ? "● \(s.device ?? "device")" : "○ no device") + " · " + s.mode
    }

    func teleport() { guard let c = selected else { return }; run { try await $0.teleport(to: c) } }
    func addWaypoint() { if let c = selected { waypoints.append(c) } }
    func walk() { let w = waypoints, s = speed, l = loop; run { try await $0.walk(w, speed: s, loop: l) } }
    func stop() { run { try await $0.stop() } }
    func reset() { waypoints = []; run { try await $0.clear() } }

    func search(_ q: String) async {
        let r = MKLocalSearch.Request(); r.naturalLanguageQuery = q
        if let item = try? await MKLocalSearch(request: r).start().mapItems.first {
            selected = item.placemark.coordinate
            camera = .region(MKCoordinateRegion(center: item.placemark.coordinate,
                                                latitudinalMeters: 2000, longitudinalMeters: 2000))
        }
    }
}
