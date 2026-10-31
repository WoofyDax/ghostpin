import Foundation
import CoreLocation

/// Talks to the GhostPin relay running on your Mac. Works from anywhere the
/// relay URL is reachable (Cloudflare tunnel / Tailscale), including cellular.
struct RemoteBackend: SpoofBackend {
    let baseURL: URL
    let token: String

    init(urlString: String, token: String) throws {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty && !s.contains("://") { s = "https://" + s }
        guard let u = URL(string: s), !token.isEmpty else { throw SpoofError.notConfigured }
        baseURL = u; self.token = token
    }

    private func call(_ path: String, body: [String: Any]? = nil) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/" + path))
        req.timeoutInterval = 15
        req.setValue(token, forHTTPHeaderField: "X-Token")
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) {
            throw SpoofError.http(h.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    func status() async throws -> SpoofStatus {
        try JSONDecoder().decode(SpoofStatus.self, from: try await call("status"))
    }
    func teleport(to c: CLLocationCoordinate2D) async throws {
        _ = try await call("teleport", body: ["lat": c.latitude, "lng": c.longitude])
    }
    func walk(_ points: [CLLocationCoordinate2D], speed: Double, loop: Bool) async throws {
        _ = try await call("route", body: [
            "points": points.map { ["lat": $0.latitude, "lng": $0.longitude] },
            "speed_mps": speed, "loop": loop])
    }
    func stop() async throws { _ = try await call("stop", body: [:]) }
    func clear() async throws { _ = try await call("clear", body: [:]) }
}
