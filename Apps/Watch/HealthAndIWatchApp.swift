import SwiftUI
import HealthAndICore

@main
struct HealthAndIWatchApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    StoreController.shared.bootstrap()
                    WatchBridge.shared.activate()
                }
        }
    }
}

struct RootView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    RowView()
                } label: {
                    Label("Row", systemImage: "figure.rower")
                }
                NavigationLink {
                    WeightsView()
                } label: {
                    Label("Weights", systemImage: "dumbbell")
                }
                NavigationLink {
                    RecentView()
                } label: {
                    Label("Recent", systemImage: "clock")
                }
            }
            .navigationTitle("Health&I")
        }
    }
}
