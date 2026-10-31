import SwiftUI
import MapKit

struct ContentView: View {
    @EnvironmentObject var m: AppModel
    @State private var query = ""
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            MapReader { proxy in
                Map(position: $m.camera) {
                    if let s = m.selected { Marker("Target", coordinate: s).tint(.blue) }
                    if m.waypoints.count > 1 { MapPolyline(coordinates: m.waypoints).stroke(.blue, lineWidth: 4) }
                    ForEach(Array(m.waypoints.enumerated()), id: \.offset) { i, c in
                        Annotation("\(i + 1)", coordinate: c) { Circle().fill(.orange).frame(width: 12, height: 12) }
                    }
                }
                .onTapGesture { pt in if let c = proxy.convert(pt, from: .local) { m.selected = c } }
            }
            .ignoresSafeArea()

            VStack(spacing: 8) {
                HStack {
                    TextField("Search place", text: $query).textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await m.search(query) } }
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                }
                Spacer()
                panel
            }
            .padding()
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task { while true { await m.refresh(); try? await Task.sleep(nanoseconds: 3_000_000_000) } }
        .alert("Error", isPresented: .constant(m.error != nil)) { Button("OK") { m.error = nil } } message: { Text(m.error ?? "") }
    }

    var panel: some View {
        VStack(spacing: 10) {
            Text(m.statusText).font(.caption).foregroundStyle(.secondary)
            if m.mode == .onDevice && m.noLocalNetwork {
                Text("No Wi-Fi detected. On-device mode needs a Wi-Fi network (no internet required) or Personal Hotspot to be on, plus LocalDevVPN connected.")
                    .font(.caption2).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
            HStack {
                Button("Teleport") { m.teleport() }.buttonStyle(.borderedProminent).disabled(m.selected == nil)
                Button("Add stop") { m.addWaypoint() }.buttonStyle(.bordered).disabled(m.selected == nil)
                Button("Walk") { m.walk() }.buttonStyle(.borderedProminent).disabled(m.waypoints.count < 2)
            }
            HStack {
                Text("Speed \(m.speed, specifier: "%.1f") m/s").font(.caption)
                Slider(value: $m.speed, in: 0.5...30)
                Toggle("Loop", isOn: $m.loop).labelsHidden(); Text("Loop").font(.caption)
            }
            HStack {
                Button("Stop") { m.stop() }.buttonStyle(.bordered)
                Button("Reset GPS", role: .destructive) { m.reset() }.buttonStyle(.bordered)
            }
        }
        .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
