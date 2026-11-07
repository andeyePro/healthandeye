import SwiftUI
import HealthAndICore

struct CatalogueView: View {
    @Bindable var store = StoreController.shared

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Profile") { ProfileEditor(profile: $store.catalogue.profile) }
                NavigationLink("Equipment (\(store.catalogue.equipment.count))") { EquipmentList() }
                NavigationLink("Exercises (\(store.catalogue.exercises.count))") { ExerciseList() }
                NavigationLink("Zone sets (\(store.catalogue.zoneSets.count))") { ZoneSetList() }
                NavigationLink("Targets (\(store.catalogue.targets.count))") { TargetList() }
                NavigationLink("Foods (\(store.catalogue.foods.count))") { FoodList() }
            }
            .navigationTitle("Catalogue")
        }
    }
}

// MARK: - Profile

struct ProfileEditor: View {
    @Binding var profile: Profile

    var body: some View {
        Form {
            OptionalNumberField(title: "Height (cm)", value: $profile.heightCm)
            OptionalNumberField(title: "Body mass (kg)", value: $profile.bodyMassKg)
            Toggle("Date of birth set", isOn: Binding(
                get: { profile.dateOfBirth != nil },
                set: { profile.dateOfBirth = $0 ? (profile.dateOfBirth ?? Date(timeIntervalSince1970: 0)) : nil }
            ))
            if profile.dateOfBirth != nil {
                DatePicker("Date of birth", selection: Binding(
                    get: { profile.dateOfBirth ?? Date() },
                    set: { profile.dateOfBirth = $0 }
                ), displayedComponents: .date)
            }
            Picker("Sex", selection: $profile.sex) {
                Text("–").tag(Sex?.none)
                ForEach(Sex.allCases, id: \.self) { Text($0.rawValue).tag(Sex?.some($0)) }
            }
            OptionalIntField(title: "Max HR", value: $profile.maxHR)
            Picker("Max HR formula", selection: $profile.maxHRFormula) {
                Text("–").tag(MaxHRFormula?.none)
                ForEach(MaxHRFormula.allCases, id: \.self) { Text($0.rawValue).tag(MaxHRFormula?.some($0)) }
            }
            if let hr = profile.resolvedMaxHR(on: Date()) {
                LabeledContent("Resolved max HR", value: "\(hr)")
            }
            OptionalIntField(title: "Resting HR", value: $profile.restingHR)
            Picker("Units", selection: $profile.units) {
                Text("–").tag(Units?.none)
                ForEach(Units.allCases, id: \.self) { Text($0.rawValue).tag(Units?.some($0)) }
            }
            OptionalTextField(title: "Time zone", text: $profile.timeZone)
        }
        .navigationTitle("Profile")
        .onDisappear { StoreController.shared.save() }
    }
}

// MARK: - Equipment

struct EquipmentList: View {
    @Bindable var store = StoreController.shared

    var body: some View {
        List {
            ForEach($store.catalogue.equipment) { $item in
                NavigationLink {
                    EquipmentEditor(item: $item)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text([item.kind, item.massKg.map { "\(Fmt.number($0, digits: 3)) kg" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $item.enabled).labelsHidden()
                    }
                }
            }
            .onDelete { store.catalogue.equipment.remove(atOffsets: $0); store.save() }
        }
        .navigationTitle("Equipment")
        .toolbar {
            Button("Add", systemImage: "plus") {
                let id = Slug.make(prefix: "eq", name: "new", existing: store.catalogue.equipment.map(\.id))
                store.catalogue.equipment.append(Equipment(id: id, name: "New equipment"))
                store.save()
            }
        }
        .onDisappear { store.save() }
    }
}

struct EquipmentEditor: View {
    @Binding var item: Equipment
    static let kinds = ["rower", "bar", "plate", "collar", "bench", "dumbbell", "band", "other"]

    var body: some View {
        Form {
            Section {
                LabeledContent("Id", value: item.id)
                TextField("Name", text: $item.name)
                Picker("Kind", selection: $item.kind) {
                    ForEach(Array(Set(Self.kinds + [item.kind])).sorted(), id: \.self) { Text($0).tag($0) }
                }
                OptionalNumberField(title: "Mass (kg)", value: $item.massKg)
                OptionalIntField(title: "Quantity", value: $item.quantity)
                Toggle("Enabled", isOn: $item.enabled)
                OptionalTextField(title: "Notes", text: $item.notes)
            }
            NumberMapEditor(title: "Limits", map: $item.limits)
            Section("Connection") {
                OptionalTextField(title: "BLE name", text: connBinding(\.bleName))
                OptionalTextField(title: "Protocol", text: connBinding(\.protocolName))
                Toggle("Relays HR", isOn: Binding(
                    get: { item.connection?.hrRelay ?? false },
                    set: { var c = item.connection ?? Connection(); c.hrRelay = $0; item.connection = c }
                ))
            }
            StringListEditor(title: "Quirks", items: $item.quirks)
        }
        .navigationTitle(item.name)
        .onDisappear { StoreController.shared.save() }
    }

    private func connBinding(_ kp: WritableKeyPath<Connection, String?>) -> Binding<String?> {
        Binding(
            get: { item.connection?[keyPath: kp] },
            set: { var c = item.connection ?? Connection(); c[keyPath: kp] = $0; item.connection = c }
        )
    }
}

// MARK: - Exercises

struct ExerciseList: View {
    @Bindable var store = StoreController.shared

    var body: some View {
        List {
            ForEach($store.catalogue.exercises) { $item in
                NavigationLink {
                    ExerciseEditor(item: $item)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text([item.pattern, item.measure.rawValue, item.unilateral ? "unilateral" : nil].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $item.enabled).labelsHidden()
                    }
                }
            }
            .onDelete { store.catalogue.exercises.remove(atOffsets: $0); store.save() }
        }
        .navigationTitle("Exercises")
        .toolbar {
            Button("Add", systemImage: "plus") {
                let id = Slug.make(prefix: "ex", name: "new", existing: store.catalogue.exercises.map(\.id))
                store.catalogue.exercises.append(Exercise(id: id, name: "New exercise"))
                store.save()
            }
        }
        .onDisappear { store.save() }
    }
}

struct ExerciseEditor: View {
    @Binding var item: Exercise
    private var store: StoreController { StoreController.shared }

    var body: some View {
        Form {
            Section {
                LabeledContent("Id", value: item.id)
                TextField("Name", text: $item.name)
                OptionalTextField(title: "Pattern", text: $item.pattern)
                Toggle("Unilateral", isOn: $item.unilateral)
                Picker("Measured by", selection: $item.measure) {
                    ForEach(Measure.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                OptionalIntField(title: "Default rest (s)", value: $item.defaultRestSeconds)
                OptionalIntField(title: "Target reps min", value: $item.targetRepMin)
                OptionalIntField(title: "Target reps max", value: $item.targetRepMax)
                Toggle("Enabled", isOn: $item.enabled)
                OptionalTextField(title: "Notes", text: $item.notes)
            }
            Section("Equipment used") {
                ForEach(store.catalogue.equipment) { eq in
                    Toggle(eq.name, isOn: Binding(
                        get: { item.equipmentIds.contains(eq.id) },
                        set: { on in
                            item.equipmentIds.removeAll { $0 == eq.id }
                            if on { item.equipmentIds.append(eq.id) }
                        }
                    ))
                }
            }
        }
        .navigationTitle(item.name)
        .onDisappear { StoreController.shared.save() }
    }
}

// MARK: - Zone sets

struct ZoneSetList: View {
    @Bindable var store = StoreController.shared

    var body: some View {
        List {
            ForEach($store.catalogue.zoneSets) { $item in
                NavigationLink {
                    ZoneSetEditor(item: $item)
                } label: {
                    VStack(alignment: .leading) {
                        Text(item.name)
                        Text(item.zones.map { "\($0.name) \(Fmt.number($0.lower))–\(Fmt.number($0.upper))" }.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { store.catalogue.zoneSets.remove(atOffsets: $0); store.save() }
        }
        .navigationTitle("Zone sets")
        .toolbar {
            Button("Add", systemImage: "plus") {
                let id = Slug.make(prefix: "zs", name: "new", existing: store.catalogue.zoneSets.map(\.id))
                store.catalogue.zoneSets.append(ZoneSet(id: id, name: "New zone set"))
                store.save()
            }
        }
        .onDisappear { store.save() }
    }
}

struct ZoneSetEditor: View {
    @Binding var item: ZoneSet

    var body: some View {
        Form {
            Section {
                LabeledContent("Id", value: item.id)
                TextField("Name", text: $item.name)
                Picker("Metric", selection: $item.metric) {
                    ForEach(ZoneMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            Section("Zones") {
                ForEach($item.zones, id: \.self) { $zone in
                    VStack {
                        TextField("Zone name", text: $zone.name)
                        NumberField(title: "Lower", value: $zone.lower)
                        NumberField(title: "Upper", value: $zone.upper)
                    }
                }
                .onDelete { item.zones.remove(atOffsets: $0) }
                Button("Add zone") { item.zones.append(Zone(name: "Zone \(item.zones.count + 1)")) }
            }
        }
        .navigationTitle(item.name)
        .onDisappear { StoreController.shared.save() }
    }
}

// MARK: - Targets

struct TargetList: View {
    @Bindable var store = StoreController.shared

    var body: some View {
        List {
            ForEach($store.catalogue.targets) { $item in
                NavigationLink {
                    TargetEditor(item: $item)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.metric.isEmpty ? item.id : item.metric)
                            Text("\(Fmt.number(item.value)) per \(item.period.rawValue)\(item.zoneName.map { " · \($0)" } ?? "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $item.enabled).labelsHidden()
                    }
                }
            }
            .onDelete { store.catalogue.targets.remove(atOffsets: $0); store.save() }
        }
        .navigationTitle("Targets")
        .toolbar {
            Button("Add", systemImage: "plus") {
                let id = Slug.make(prefix: "tg", name: "new", existing: store.catalogue.targets.map(\.id))
                store.catalogue.targets.append(Target(id: id))
                store.save()
            }
        }
        .onDisappear { store.save() }
    }
}

struct TargetEditor: View {
    @Binding var item: Target
    private var store: StoreController { StoreController.shared }
    static let metrics = ["minutes_in_zone", "energy_kcal", "protein_g", "distance_m", "sessions", "steps"]

    var body: some View {
        Form {
            LabeledContent("Id", value: item.id)
            TextField("Metric", text: $item.metric)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Menu("Common metrics") {
                ForEach(Self.metrics, id: \.self) { m in Button(m) { item.metric = m } }
            }
            Picker("Period", selection: $item.period) {
                ForEach(Period.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            NumberField(title: "Value", value: $item.value)
            Picker("Zone set", selection: $item.zoneSetId) {
                Text("–").tag(String?.none)
                ForEach(store.catalogue.zoneSets) { Text($0.name).tag(String?.some($0.id)) }
            }
            if let zs = store.catalogue.zoneSets.first(where: { $0.id == item.zoneSetId }) {
                Picker("Zone", selection: $item.zoneName) {
                    Text("–").tag(String?.none)
                    ForEach(zs.zones, id: \.name) { Text($0.name).tag(String?.some($0.name)) }
                }
            }
            Toggle("Enabled", isOn: $item.enabled)
        }
        .navigationTitle(item.metric.isEmpty ? "Target" : item.metric)
        .onDisappear { StoreController.shared.save() }
    }
}

// MARK: - Foods

struct FoodList: View {
    @Bindable var store = StoreController.shared

    var body: some View {
        List {
            ForEach($store.catalogue.foods) { $item in
                NavigationLink(item.name) { FoodEditor(item: $item) }
            }
            .onDelete { store.catalogue.foods.remove(atOffsets: $0); store.save() }
        }
        .navigationTitle("Foods")
        .toolbar {
            Button("Add", systemImage: "plus") {
                let id = Slug.make(prefix: "fd", name: "new", existing: store.catalogue.foods.map(\.id))
                store.catalogue.foods.append(Food(id: id, name: "New food"))
                store.save()
            }
        }
        .onDisappear { store.save() }
    }
}

struct FoodEditor: View {
    @Binding var item: Food

    var body: some View {
        Form {
            Section {
                LabeledContent("Id", value: item.id)
                TextField("Name", text: $item.name)
            }
            NumberMapEditor(title: "Per 100 g", map: $item.per100g)
            Section("Servings") {
                ForEach(item.servings.indices, id: \.self) { i in
                    HStack {
                        TextField("Name", text: Binding(
                            get: { i < item.servings.count ? item.servings[i].name : "" },
                            set: { if i < item.servings.count { item.servings[i].name = $0 } }
                        ))
                        TextField("g", value: Binding(
                            get: { i < item.servings.count ? item.servings[i].grams : 0 },
                            set: { if i < item.servings.count { item.servings[i].grams = $0 } }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
                        Text("g")
                    }
                }
                .onDelete { item.servings.remove(atOffsets: $0) }
                Button("Add serving") { item.servings.append(Serving(name: "serving", grams: 100)) }
            }
        }
        .navigationTitle(item.name)
        .onDisappear { StoreController.shared.save() }
    }
}
