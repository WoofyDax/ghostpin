import SwiftUI
import UniformTypeIdentifiers

struct HelpView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var importing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Change where your iPhone thinks it is. Pick a spot, tap Spoof, done.")
                        .font(.title3.weight(.semibold))

                    card("Before you start", icon: "checklist") {
                        check("GhostPin is paired with this iPhone", ok: m.pairingReady)
                        check("LocalDevVPN is connected", ok: m.vpnOn)
                        if !m.pairingReady {
                            Text("Not paired? Run the installer on your Mac again (see the guide on GitHub), or import a pairing file here.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Import a pairing file") { importing = true }.font(.footnote)
                        }
                        if !m.vpnOn {
                            Text("Open the free LocalDevVPN app and tap Connect, then come back here.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    card("On Wi-Fi (easiest)", icon: "wifi") {
                        step(1, "Open LocalDevVPN and tap **Connect**.")
                        step(2, "Come back here, pick a place, and tap **Spoof this location**.")
                        step(3, "That's it. You can now turn Wi-Fi off and keep going on cellular. The spoof keeps working.")
                    }

                    card("No Wi-Fi (cellular only)", icon: "antenna.radiowaves.left.and.right") {
                        step(1, "Open LocalDevVPN and tap **Connect**.")
                        step(2, "Turn **Cellular Data off** (Settings > Cellular).")
                        step(3, "Come back here, pick a place, and tap **Spoof this location**.")
                        step(4, "Turn **Cellular Data back on**. Your spoofed location now stays on.")
                    }

                    card("Good to know", icon: "info.circle") {
                        bullet("To go back to normal, tap **Stop & use my real location**.")
                        bullet("Keep LocalDevVPN connected while you use GhostPin.")
                        bullet("Moving to a new place later? Do the same steps again.")
                        bullet("With a free Apple ID, the app stops opening after 7 days. Plug into your Mac and run the installer again.")
                        bullet("Some apps and games detect fake locations. Use at your own risk.")
                    }
                }
                .padding()
            }
            .navigationTitle("How to use GhostPin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .propertyList]) { r in
                if case .success(let u) = r, u.startAccessingSecurityScopedResource() {
                    if let d = try? Data(contentsOf: u) { m.importPairing(d) }
                    u.stopAccessingSecurityScopedResource()
                }
            }
        }
    }

    func card<C: View>(_ title: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    func check(_ text: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? .green : .secondary)
            Text(text)
        }
    }

    func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.footnote.bold()).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Color.blue, in: Circle())
            Text(text)
        }
    }

    func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) { Text("•"); Text(text) }.font(.callout)
    }
}
