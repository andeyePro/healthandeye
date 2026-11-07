import SwiftUI
import HealthAndICore

enum AppTab: Hashable { case today, log, row, weights, catalogue, settings }

@MainActor @Observable
final class Navigation {
    static let shared = Navigation()
    var tab: AppTab = .today
}

struct RootView: View {
    @State private var nav = Navigation.shared
    private var store: StoreController { StoreController.shared }

    var body: some View {
        TabView(selection: $nav.tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)
            LogView()
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.log)
            if store.isOn(.rowing) {
                RowView()
                    .tabItem { Label("Row", systemImage: "figure.rower") }
                    .tag(AppTab.row)
            }
            if store.isOn(.weights) {
                WeightsView()
                    .tabItem { Label("Weights", systemImage: "dumbbell") }
                    .tag(AppTab.weights)
            }
            CatalogueView()
                .tabItem { Label("Catalogue", systemImage: "books.vertical") }
                .tag(AppTab.catalogue)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(AppTab.settings)
        }
        .overlay(alignment: .top) {
            if let err = store.lastError {
                Text(err)
                    .font(.caption)
                    .padding(8)
                    .background(.red.opacity(0.85), in: .rect(cornerRadius: 8))
                    .foregroundStyle(.white)
                    .onTapGesture { StoreController.shared.lastError = nil }
                    .padding(.top, 4)
            }
        }
    }
}
