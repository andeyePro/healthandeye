import SwiftUI
import HealthAndICore

@main
struct HealthAndIApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = StoreController.shared
    @State private var booted = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    guard !booted else { return }
                    booted = true
                    store.bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, booted { store.reloadCatalogueIfChanged() }
                }
                .alert("Catalogue changed on disk", isPresented: Binding(
                    get: { store.pendingDiff != nil },
                    set: { if !$0 && store.pendingDiff != nil { store.rejectPendingDiff() } }
                )) {
                    Button("Use the files") { store.acceptPendingDiff() }
                    Button("Keep the app's copy", role: .destructive) { store.rejectPendingDiff() }
                } message: {
                    Text("Catalogue changed on disk:\n" + (store.pendingDiff?.lines.joined(separator: "\n") ?? ""))
                }
                .alert("Empty folder", isPresented: Binding(
                    get: { store.needsStarterPackChoice },
                    set: { _ in }
                )) {
                    Button("Load starter pack") { store.chooseStarterPack(true) }
                    Button("Start empty") { store.chooseStarterPack(false) }
                } message: {
                    Text("The export folder has no catalogue yet. Seed it with the starter pack (today's kit, all deletable), or start empty?")
                }
        }
    }
}
