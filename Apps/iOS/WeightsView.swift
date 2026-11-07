import SwiftUI
import HealthAndICore

@MainActor @Observable
final class WeightsSession {
    static let shared = WeightsSession()

    var session: Session?
    var exerciseId: String?
    var side: Side = .left
    var reps: Int?
    var seconds: Double?
    var meters: Double?
    var load = Load()
    var effort: Double?
    var tags: [String] = []
    var notes: String?
    let rest = RestTimer()

    private var store: StoreController { StoreController.shared }

    var exercise: Exercise? { exerciseId.flatMap { store.catalogue.exercise(id: $0) } }

    var rememberedTags: [String] {
        let saved = UserDefaults.standard.stringArray(forKey: "variant_tags") ?? []
        let used = store.sessions.flatMap { $0.sets.flatMap(\.variantTags) }
        return Array(Set(saved + used)).sorted()
    }

    func remember(tag: String) {
        var saved = UserDefaults.standard.stringArray(forKey: "variant_tags") ?? []
        if !saved.contains(tag) { saved.append(tag) }
        UserDefaults.standard.set(saved, forKey: "variant_tags")
    }

    func begin() {
        let now = Date()
        session = Session(id: SessionID.make(start: now, type: "weights"), start: now, type: "weights")
        exerciseId = nil
    }

    func select(_ ex: Exercise) {
        exerciseId = ex.id
        side = ex.unilateral ? .left : .both
        let last = (session?.sets.reversed() ?? []).first { $0.exerciseId == ex.id }
            ?? store.sessions.reversed().lazy.flatMap { $0.sets.reversed() }.first { $0.exerciseId == ex.id }
        load = last?.load ?? Load()
        reps = last?.reps
        seconds = last?.seconds
        meters = last?.meters
        effort = nil
        tags = last?.variantTags ?? []
        notes = nil
    }

    func logSet() {
        guard var s = session, let ex = exercise else { return }
        var entry = SetEntry(
            id: "set-\(s.sets.count + 1)", exerciseId: ex.id, side: side,
            reps: ex.measure == .reps || ex.measure == .strokes ? reps : nil,
            seconds: ex.measure == .time ? seconds : nil,
            meters: ex.measure == .distance ? meters : nil,
            load: (load.parts.isEmpty && load.fixedKg == nil) ? nil : load,
            variantTags: tags, notes: notes, timestamp: Date())
        if store.catalogue.settings.effortScale == .rir { entry.rir = effort } else { entry.rpe = effort }
        if rest.isRunning { rest.apply(to: &entry) }
        s.sets.append(entry)
        if !ex.equipmentIds.isEmpty {
            s.equipmentIds = Array(Set(s.equipmentIds + ex.equipmentIds)).sorted()
        }
        session = s
        store.saveSession(s)
        notes = nil
        if ex.unilateral { side = side == .left ? .right : .left }
        rest.start(for: ex)
    }

    func deleteSets(at offsets: IndexSet) {
        guard var s = session else { return }
        s.sets.remove(atOffsets: offsets)
        session = s
        store.saveSession(s)
    }

    var hints: [Hint] {
        guard let s = session, store.catalogue.settings.progression.enabled else { return [] }
        return ProgressionAdvisor.hints(for: s, history: store.sessions.filter { $0.id != s.id }, catalogue: store.catalogue)
    }

    func finish() {
        _ = rest.stop()
        guard var s = session else { return }
        s.end = Date()
        session = nil
        exerciseId = nil
        guard !s.sets.isEmpty else { return }
        store.saveSession(s)
        store.writeDerived()
        HealthPush.workout(s, activity: .traditionalStrengthTraining)
    }
}

struct WeightsView: View {
    @State private var model = WeightsSession.shared
    @State private var showPicker = false
    private var store: StoreController { StoreController.shared }

    var body: some View {
        NavigationStack {
            Group {
                if model.session == nil {
                    ContentUnavailableView {
                        Label("Free weights", systemImage: "dumbbell")
                    } description: {
                        Text("Start a session, pick an exercise, log sets.")
                    } actions: {
                        Button("Start session") { model.begin(); showPicker = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    sessionForm
                }
            }
            .navigationTitle("Weights")
            .sheet(isPresented: $showPicker) {
                ExercisePicker { ex in model.select(ex); showPicker = false }
            }
        }
    }

    private var sessionForm: some View {
        Form {
            let hints = model.hints
            if !hints.isEmpty {
                Section {
                    ForEach(Array(hints.enumerated()), id: \.offset) { _, h in
                        Label(h.message, systemImage: "lightbulb").font(.callout)
                    }
                }
                .listRowBackground(Color.yellow.opacity(0.2))
            }
            if model.rest.isRunning {
                RestTimerSection(rest: model.rest)
            }
            Section {
                Button(model.exercise?.name ?? "Pick exercise…") { showPicker = true }
                    .font(.headline)
            }
            if let ex = model.exercise {
                SetEntrySection(model: model, exercise: ex)
            }
            if let s = model.session, !s.sets.isEmpty {
                Section("Logged (\(s.sets.count))") {
                    ForEach(s.sets.reversed()) { set in SetRow(set: set) }
                        .onDelete { idx in
                            let n = s.sets.count
                            model.deleteSets(at: IndexSet(idx.map { n - 1 - $0 }))
                        }
                }
            }
            Section {
                Button("Finish session") { model.finish() }
                    .bold()
                Button("Discard session", role: .destructive) {
                    _ = model.rest.stop()
                    model.session = nil
                }
                .disabled(!(model.session?.sets.isEmpty ?? true))
            }
        }
    }
}

struct RestTimerSection: View {
    let rest: RestTimer

    var body: some View {
        Section("Rest") {
            HStack {
                Text(Fmt.duration(rest.elapsed))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(rest.hasFinished ? .green : .primary)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("target \(Fmt.duration(Double(rest.targetSeconds)))").font(.caption)
                    if rest.interruptions > 0 { Text("interrupted ×\(rest.interruptions)").font(.caption2) }
                }
            }
            HStack {
                Button(rest.isPaused ? "Resume" : "Interrupt") {
                    if rest.isPaused { rest.resume() } else { rest.interrupt() }
                }
                Spacer()
                Button("+30 s") { rest.add(seconds: 30) }
            }
            .buttonStyle(.bordered)
        }
    }
}

struct ExercisePicker: View {
    let onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    private var store: StoreController { StoreController.shared }

    var body: some View {
        NavigationStack {
            List {
                let enabled = store.catalogue.exercises.filter(\.enabled)
                if enabled.isEmpty {
                    Text("No enabled exercises. Add some in Catalogue.").foregroundStyle(.secondary)
                }
                ForEach(enabled) { ex in
                    Button {
                        onPick(ex)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(ex.name)
                            Text([ex.pattern, ex.measure.rawValue, ex.unilateral ? "unilateral" : nil].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Exercise")
            .toolbar { Button("Cancel") { dismiss() } }
        }
    }
}

struct SetEntrySection: View {
    @Bindable var model: WeightsSession
    let exercise: Exercise
    @State private var newTag = ""
    @State private var showLoad = false
    private var store: StoreController { StoreController.shared }

    var body: some View {
        let scale = store.catalogue.settings.effortScale
        let cat = store.catalogue
        Section("Set") {
            if exercise.unilateral {
                Picker("Side", selection: $model.side) {
                    Text("Left").tag(Side.left)
                    Text("Right").tag(Side.right)
                }
                .pickerStyle(.segmented)
            }
            switch exercise.measure {
            case .reps, .strokes:
                Stepper(value: Binding(get: { model.reps ?? 0 }, set: { model.reps = $0 }), in: 0...500) {
                    LabeledContent(exercise.measure == .reps ? "Reps" : "Strokes", value: model.reps.map(String.init) ?? "–")
                }
                if let lo = exercise.targetRepMin, let hi = exercise.targetRepMax {
                    Text("Target \(lo)–\(hi)").font(.caption).foregroundStyle(.secondary)
                }
            case .time:
                OptionalNumberField(title: "Seconds", value: $model.seconds)
            case .distance:
                OptionalNumberField(title: "Metres", value: $model.meters)
            }
            Button {
                showLoad = true
            } label: {
                LabeledContent("Load") {
                    if let kg = LoadBuilder.totalKg(model.load, catalogue: cat) {
                        Text("\(Fmt.number(kg, digits: 2)) kg\(model.load.perHand ? " /hand" : "")")
                    } else {
                        Text("none")
                    }
                }
            }
            ForEach(LoadBuilder.limitWarnings(load: model.load, exercise: exercise, catalogue: cat), id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
            }
            Stepper(value: Binding(get: { model.effort ?? (scale == .rir ? 2 : 8) },
                                   set: { model.effort = $0 }),
                    in: 0...10, step: 0.5) {
                LabeledContent(scale == .rir ? "RIR" : "RPE", value: model.effort.map { Fmt.number($0) } ?? "–")
            }
            OptionalTextField(title: "Notes", text: $model.notes)
        }
        Section("Variant tags") {
            let all = Array(Set(model.rememberedTags + model.tags)).sorted()
            ForEach(all, id: \.self) { tag in
                Toggle(tag, isOn: Binding(
                    get: { model.tags.contains(tag) },
                    set: { on in
                        model.tags.removeAll { $0 == tag }
                        if on { model.tags.append(tag) }
                    }
                ))
            }
            HStack {
                TextField("new tag", text: $newTag)
                Button("Add") {
                    let t = newTag.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    model.remember(tag: t)
                    if !model.tags.contains(t) { model.tags.append(t) }
                    newTag = ""
                }
            }
        }
        Section {
            Button {
                model.logSet()
            } label: {
                Text(model.rest.isRunning ? "Log set (ends rest)" : "Log set")
                    .frame(maxWidth: .infinity)
                    .bold()
            }
            .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $showLoad) {
            LoadBuilderView(load: $model.load, exercise: exercise)
        }
    }
}

struct LoadBuilderView: View {
    @Binding var load: Load
    let exercise: Exercise?
    @Environment(\.dismiss) private var dismiss
    private var store: StoreController { StoreController.shared }

    private var components: [Equipment] {
        let loadable: Set<String> = ["bar", "plate", "collar", "dumbbell", "other", "band"]
        let eq = store.catalogue.equipment.filter { $0.enabled && $0.massKg != nil && loadable.contains($0.kind) }
        let used = Set(load.parts.map(\.equipmentId))
        let extra = store.catalogue.equipment.filter { used.contains($0.id) && !eq.contains($0) }
        return eq + extra
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    let cat = store.catalogue
                    LabeledContent("Total") {
                        Text(LoadBuilder.totalKg(load, catalogue: cat).map { "\(Fmt.number($0, digits: 3)) kg" } ?? "–")
                            .font(.title3.bold())
                    }
                    ForEach(Array(LoadBuilder.breakdown(load, catalogue: cat).enumerated()), id: \.offset) { _, b in
                        Text("\(b.count) × \(b.name) = \(Fmt.number(b.kg, digits: 3)) kg").font(.caption)
                    }
                    ForEach(LoadBuilder.limitWarnings(load: load, exercise: exercise, catalogue: cat), id: \.self) { w in
                        Label(w, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    Toggle("Per hand", isOn: $load.perHand)
                    OptionalNumberField(title: "Fixed kg (no components)", value: $load.fixedKg)
                    OptionalTextField(title: "Label", text: $load.label)
                }
                Section("Components") {
                    ForEach(components) { eq in
                        Stepper(value: count(for: eq.id), in: 0...20) {
                            LabeledContent(eq.name) {
                                Text("\(count(for: eq.id).wrappedValue) × \(Fmt.number(eq.massKg ?? 0, digits: 3)) kg")
                            }
                        }
                    }
                }
                Section {
                    Button("Clear") { load = Load(perHand: load.perHand) }
                }
            }
            .navigationTitle("Load")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func count(for id: String) -> Binding<Int> {
        Binding(
            get: { load.parts.first { $0.equipmentId == id }?.count ?? 0 },
            set: { n in
                if let i = load.parts.firstIndex(where: { $0.equipmentId == id }) {
                    if n == 0 { load.parts.remove(at: i) } else { load.parts[i].count = n }
                } else if n > 0 {
                    load.parts.append(LoadPart(equipmentId: id, count: n))
                }
            }
        )
    }
}
