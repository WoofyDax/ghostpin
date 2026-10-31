// Loopback tunnel used by GhostPin.
//
// Based on LocalDevVPN / StosVPN by the SideStore Team and Stossy11 (https://github.com/jkcoxson/LocalDevVPN).
// Idea: route one private address (10.7.0.1) into this tunnel and bounce every packet straight back with
// its source and destination swapped, so the phone can talk to its own services at that address.
import NetworkExtension

class PacketTunnelProvider: NEPacketTunnelProvider {
    static let ifaceIP = "10.7.1.1"
    static let peerIP = "10.7.0.1"

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let iface = NEIPv4Settings(addresses: [Self.ifaceIP], subnetMasks: ["255.255.255.0"])
        iface.includedRoutes = [NEIPv4Route(destinationAddress: Self.peerIP, subnetMask: "255.255.255.255")]
        iface.excludedRoutes = [.default()]

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: Self.peerIP)
        settings.ipv4Settings = iface
        setTunnelNetworkSettings(settings) { error in
            if let error { return completionHandler(error) }
            self.bounce()
            completionHandler(nil)
        }
    }

    private func bounce() {
        packetFlow.readPackets { [self] packets, protocols in
            var out = packets
            for i in out.indices where protocols[i].int32Value == AF_INET && out[i].count >= 20 {
                out[i].withUnsafeMutableBytes { bytes in
                    guard let p = bytes.baseAddress?.assumingMemoryBound(to: UInt32.self) else { return }
                    let src = p[3], dst = p[4]
                    p[3] = dst; p[4] = src
                }
            }
            packetFlow.writePackets(out, withProtocols: protocols)
            bounce()
        }
    }
}
