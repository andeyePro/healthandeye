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
                    // Headless testing hooks: `--starter-pack` seeds an empty folder without the
                    // alert; `--tab <name>` opens a tab. Used by scripts/mac-test.sh simulator runs.
                    let args = ProcessInfo.processInfo.arguments
                    if args.contains("--starter-pack"), store.needsStarterPackChoice { store.chooseStarterPack(true) }
                    if let i = args.firstIndex(of: "--tab"), i + 1 < args.count {
                        switch args[i + 1] {
                        case "log": Navigation.shared.tab = .log
                        case "row": Navigation.shared.tab = .row
                        case "weights": Navigation.shared.tab = .weights
                        case "catalogue": Navigation.shared.tab = .catalogue
                        case "settings": Navigation.shared.tab = .settings
                        default: break
                        }
                    }
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
