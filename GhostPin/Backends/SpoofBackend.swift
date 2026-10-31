import Foundation
import CoreLocation

struct SpoofStatus: Decodable {
    var connected: Bool
    var device: String?
    var mode: String
    var lat: Double?
    var lng: Double?
    var progress: Double?
}

protocol SpoofBackend {
    func status() async throws -> SpoofStatus
    func teleport(to c: CLLocationCoordinate2D) async throws
    func walk(_ points: [CLLocationCoordinate2D], speed: Double, loop: Bool) async throws
    func stop() async throws
    func clear() async throws
}

enum SpoofError: LocalizedError {
    case notConfigured, http(Int, String), unsupported(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Enter your relay URL and token in Settings."
        case .http(let c, let m): return "Relay error \(c): \(m)"
        case .unsupported(let m): return m
        }
    }
}
