import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $m.modeRaw) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                if m.mode == .remote {
                    Section("Mac relay (works over cellular via tunnel)") {
                        TextField("https://xxxx.trycloudflare.com", text: $m.relayURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        SecureField("Access token", text: $m.relayToken)
                    }
                    Text("On your Mac run GhostPin/run.sh. It prints the public URL and token (~/.ghostpin/token).")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Section("On-device (LocalDevVPN)") {
                        Button(m.pairing == nil ? "Import pairing file" : "Pairing file loaded ✓") { importing = true }
                        Text("1) Install LocalDevVPN and tap Connect. 2) Import this phone's pairing file (see README). Then it works with no computer.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .propertyList]) { r in
                if case .success(let u) = r, u.startAccessingSecurityScopedResource() {
                    m.pairing = try? Data(contentsOf: u); u.stopAccessingSecurityScopedResource()
                }
            }
        }
    }
}
