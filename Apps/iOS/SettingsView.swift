import SwiftUI
import HealthAndICore

struct SettingsView: View {
    @Bindable var store = StoreController.shared
    @State private var pickFolder = false
    @State private var confirmStarter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Modules") {
                    ForEach(Module.allCases, id: \.self) { m in
                        Toggle(Self.title(m), isOn: Binding(
                            get: { store.isOn(m) },
                            set: { on in
                                store.set(m, on: on)
                                if on && (m == .healthKitRead || m == .healthKitWrite) {
                                    Task { await HealthKitService.shared.requestForEnabledModules() }
                                }
                            }
                        ))
                    }
                }
                Section("Logging") {
                    Picker("Effort scale", selection: $store.catalogue.settings.effortScale) {
                        Text("RIR").tag(EffortScale.rir)
                        Text("RPE").tag(EffortScale.rpe)
                    }
                    LabeledContent("Set notation") {
                        TextField("reps@RIR", text: $store.catalogue.settings.setNotation)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                    }
                    Toggle("Zone cues (haptic + voice)", isOn: $store.catalogue.settings.zoneCues)
                    Toggle("Energy: prefer HR estimate", isOn: $store.catalogue.settings.energyPrefersHR)
                }
                Section("Progression hints") {
                    Toggle("Enabled", isOn: $store.catalogue.settings.progression.enabled)
                    Stepper("Too light: reps above target max by \(store.catalogue.settings.progression.tooLightRepsAbove)",
                            value: $store.catalogue.settings.progression.tooLightRepsAbove, in: 0...20)
                    Stepper("Too light: RIR at least \(Fmt.number(store.catalogue.settings.progression.tooLightRirAtLeast))",
                            value: $store.catalogue.settings.progression.tooLightRirAtLeast, in: 0...10, step: 0.5)
                    Stepper("Under-warmed: rep rise \(store.catalogue.settings.progression.underWarmedRepRise)",
                            value: $store.catalogue.settings.progression.underWarmedRepRise, in: 0...20)
                }
                NavigationLink("HUD tiles") { HUDTileOrderView() }
                Section("Export folder") {
                    Text(store.rootURL.path).font(.caption).textSelection(.enabled)
                    Button("Choose folder…") { pickFolder = true }
                    if store.isUsingCustomFolder {
                        Button("Use default folder") { store.resetFolder() }
                    }
                    Button("Rebuild export files") { store.writeDerived() }
                    Button("Load starter pack…") { confirmStarter = true }
                }
                Section("About") {
                    LabeledContent("Health&I", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    Text("Local-first: your data stays on this device and in the folder you choose. Licensed AGPL-3.0. Source: github.com/andeyePro/healthandeye")
                        .font(.caption)
                }
            }
            .navigationTitle("Settings")
            .onDisappear { store.save() }
            .onChange(of: store.catalogue.settings) { store.save() }
            .fileImporter(isPresented: $pickFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { store.chooseFolder(url: url) }
            }
            .confirmationDialog("Replace the catalogue with the starter pack?", isPresented: $confirmStarter, titleVisibility: .visible) {
                Button("Load starter pack", role: .destructive) { store.chooseStarterPack(true) }
            } message: {
                Text("Your current equipment, exercises, zones, targets, foods and settings are replaced.")
            }
        }
    }

    static func title(_ m: Module) -> String {
        switch m {
        case .rowing: "Rowing"
        case .weights: "Free weights"
        case .nutrition: "Nutrition"
        case .body: "Body metrics"
        case .healthKitRead: "Apple Health: read"
        case .healthKitWrite: "Apple Health: write"
        case .export: "Export for Claude"
        case .advice: "Advice cards"
        }
    }
}

struct HUDTileOrderView: View {
    @Bindable var store = StoreController.shared

    var body: some View {
        List {
            Section("Shown (drag to reorder)") {
                ForEach(store.catalogue.settings.hudTiles, id: \.self) { Text(HUDTile.title($0)) }
                    .onMove { store.catalogue.settings.hudTiles.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { store.catalogue.settings.hudTiles.remove(atOffsets: $0) }
            }
            Section("Hidden") {
                ForEach(HUDTile.all.filter { !store.catalogue.settings.hudTiles.contains($0) }, id: \.self) { t in
                    Button("Show \(HUDTile.title(t))") { store.catalogue.settings.hudTiles.append(t) }
                }
            }
        }
        .navigationTitle("HUD tiles")
        .toolbar { EditButton() }
        .onDisappear { store.save() }
    }
}
