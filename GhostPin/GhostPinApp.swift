import SwiftUI

@main
struct GhostPinApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(model) }
    }
}
