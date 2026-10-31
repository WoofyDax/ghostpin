import Foundation
import NetworkExtension

/// Starts and stops GhostPin's built-in loopback tunnel (the `GhostPinTunnel` extension).
/// Replaces the separate LocalDevVPN app. Tunnel idea: LocalDevVPN / StosVPN (see NOTICE.md).
@MainActor
final class TunnelManager {
    var onChange: ((NEVPNStatus) -> Void)?
    private var manager: NETunnelProviderManager?
    private var observer: NSObjectProtocol?

    static var tunnelBundleId: String { (Bundle.main.bundleIdentifier ?? "com.example.ghostpin") + ".tunnel" }
    static let addresses = ["10.7.0.1", "10.7.1.1"]

    var status: NEVPNStatus { manager?.connection.status ?? .invalid }

    private func observe(_ m: NETunnelProviderManager) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: m.connection, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.onChange?(self.status)
            }
        }
    }

    private func loadOrCreate() async throws -> NETunnelProviderManager {
        let all = try await NETunnelProviderManager.loadAllFromPreferences()
        let mine = all.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == Self.tunnelBundleId }
        let m = mine ?? NETunnelProviderManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = Self.tunnelBundleId
        proto.serverAddress = "GhostPin private tunnel"
        m.protocolConfiguration = proto
        m.localizedDescription = "GhostPin"
        // Reconnect automatically whenever something talks to the tunnel addresses.
        let rule = NEOnDemandRuleEvaluateConnection()
        rule.interfaceTypeMatch = .any
        rule.connectionRules = [NEEvaluateConnectionRule(matchDomains: Self.addresses, andAction: .connectIfNeeded)]
        m.onDemandRules = [rule]
        m.isOnDemandEnabled = true
        m.isEnabled = true
        try await m.saveToPreferences()   // first time: iOS asks "Allow GhostPin to add VPN configurations"
        try await m.loadFromPreferences()
        return m
    }

    /// Makes sure the tunnel is running; waits briefly for it to connect.
    func ensureRunning() async throws {
        let m = try await loadOrCreate()
        manager = m
        observe(m)
        onChange?(m.connection.status)
        if m.connection.status != .connected && m.connection.status != .connecting {
            try m.connection.startVPNTunnel()
        }
        for _ in 0..<30 {
            if m.connection.status == .connected { onChange?(.connected); return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    func stop() { manager?.connection.stopVPNTunnel() }
}
