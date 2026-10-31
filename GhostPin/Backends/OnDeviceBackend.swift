import Foundation
import CoreLocation

/// Standalone mode: the phone talks to its own developer location service over
/// the LocalDevVPN loopback tunnel (10.7.0.x), using a pairing file exported
/// from a computer. The native client is `IDeviceLocationClient` (idevice Rust
/// library, Native/IDevice.xcframework).
protocol DeviceLocationClient {
    func connect(pairingFile: Data, host: String) async throws
    func setLocation(_ c: CLLocationCoordinate2D) async throws
    func clearLocation() async throws
}

final class OnDeviceBackend: SpoofBackend {
    static var client: DeviceLocationClient? = IDeviceLocationClient()
    static let tunnelHost = "10.7.0.1"         // LocalDevVPN loopback address
    private var task: Task<Void, Never>?
    private var last: CLLocationCoordinate2D?
    private let pairing: Data

    /// `pairingFile` may be empty when only the RemotePairing file is used.
    init(pairingFile: Data = Data()) { pairing = pairingFile }

    private func ready() async throws -> DeviceLocationClient {
        guard let c = Self.client else {
            throw SpoofError.unsupported("Native location client unavailable.")
        }
        try await c.connect(pairingFile: pairing, host: Self.tunnelHost)
        return c
    }

    func status() async throws -> SpoofStatus {
        SpoofStatus(connected: Self.client != nil, device: "This iPhone", mode: task == nil ? "idle" : "route",
                    lat: last?.latitude, lng: last?.longitude, progress: nil)
    }
    func teleport(to c: CLLocationCoordinate2D) async throws {
        task?.cancel(); task = nil
        try await ready().setLocation(c); last = c
    }
    func walk(_ pts: [CLLocationCoordinate2D], speed: Double, loop: Bool) async throws {
        let client = try await ready()
        task?.cancel()
        task = Task { [weak self] in
            repeat {
                for (a, b) in zip(pts, pts.dropFirst()) {
                    let d = CLLocation(latitude: a.latitude, longitude: a.longitude)
                        .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
                    let n = max(1, Int(d / speed))
                    for i in 1...n {
                        if Task.isCancelled { return }
                        let f = Double(i) / Double(n)
                        let p = CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * f,
                                                       longitude: a.longitude + (b.longitude - a.longitude) * f)
                        try? await client.setLocation(p); self?.last = p
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }
            } while loop && !Task.isCancelled
            self?.task = nil
        }
    }
    func stop() async throws { task?.cancel(); task = nil }
    func clear() async throws { try await stop(); try await ready().clearLocation(); last = nil }
}
