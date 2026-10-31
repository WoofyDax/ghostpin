import SwiftUI

struct RouteSheet: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("1. Tap the map to pick a point.\n2. Tap \"Add this point\". Repeat for each stop.\n3. Tap Start.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button { m.addWaypoint() } label: {
                        Label("Add this point (\(m.waypoints.count) added)", systemImage: "plus.circle.fill")
                    }
                    .disabled(m.selected == nil)
                }
                Section("How fast?") {
                    Picker("Speed", selection: $m.pace) {
                        ForEach(Pace.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Repeat forever", isOn: $m.loop)
                }
                Section {
                    Button { m.startRoute() } label: {
                        Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(m.waypoints.count < 2 || m.busy)
                    Button("Clear points", role: .destructive) { m.waypoints = [] }
                        .disabled(m.waypoints.isEmpty)
                }
            }
            .navigationTitle("Walk a route")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
