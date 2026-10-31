import SwiftUI
import MapKit

struct ContentView: View {
    @EnvironmentObject var m: AppModel
    @State private var query = ""
    @FocusState private var searching: Bool

    var body: some View {
        ZStack {
            MapReader { proxy in
                Map(position: $m.camera) {
                    if let s = m.selected {
                        Marker(m.selectedName.isEmpty ? "Chosen spot" : m.selectedName, coordinate: s).tint(m.isSpoofing ? .green : .blue)
                    }
                    if m.waypoints.count > 1 { MapPolyline(coordinates: m.waypoints).stroke(.blue, lineWidth: 4) }
                    ForEach(Array(m.waypoints.enumerated()), id: \.offset) { i, c in
                        Annotation("\(i + 1)", coordinate: c) {
                            Circle().fill(.orange).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                }
                .onTapGesture { pt in
                    if let c = proxy.convert(pt, from: .local) { m.selected = c; m.selectedName = ""; searching = false }
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomCard
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $m.showHelp) { HelpView().environmentObject(m) }
        .sheet(isPresented: $m.showRoute) { RouteSheet().environmentObject(m).presentationDetents([.medium]) }
        .alert("Couldn't do that", isPresented: Binding(get: { m.error != nil }, set: { if !$0 { m.error = nil } })) {
            Button("OK", role: .cancel) {}
            Button("How to fix") { m.showHelp = true }
        } message: { Text(m.error ?? "") + Text(m.errorDetails.map { "\n\nDetails: \($0)" } ?? "").font(.caption2) }
    }

    var topBar: some View {
        HStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search for a place", text: $query)
                    .focused($searching)
                    .submitLabel(.search)
                    .onSubmit { Task { await m.search(query) } }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                }
            }
            .padding(12)
            .background(.regularMaterial, in: Capsule())

            Button { m.showHelp = true } label: {
                Image(systemName: "questionmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
        }
    }

    var bottomCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(m.statusColor).frame(width: 10, height: 10)
                Text(m.statusText).font(.subheadline.weight(.medium)).lineLimit(2)
                Spacer()
            }

            if m.isSpoofing {
                Button(role: .destructive) { m.stopSpoofing() } label: {
                    bigLabel("Stop & use my real location", icon: "location.slash.fill")
                }
                .buttonStyle(.borderedProminent).tint(.red)
            } else {
                Button { m.spoof() } label: {
                    bigLabel(m.selected == nil ? "Pick a spot on the map" : "Spoof this location", icon: "location.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(m.selected == nil || m.busy)
            }

            if m.selected != nil && m.isSpoofing {
                Button { m.spoof() } label: { Label("Move to the new spot", systemImage: "arrow.triangle.turn.up.right.circle") }
                    .buttonStyle(.bordered)
            }

            HStack {
                Button { m.showRoute = true } label: { Label("Walk a route", systemImage: "figure.walk") }
                    .buttonStyle(.bordered)
                Spacer()
                if m.busy { ProgressView() }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .shadow(radius: 8, y: 2)
    }

    func bigLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }
}
