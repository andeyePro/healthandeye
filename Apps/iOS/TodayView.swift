import SwiftUI
import HealthAndICore

struct TodayView: View {
    @State private var healthMetrics: [String: Double] = [:]
    private var store: StoreController { StoreController.shared }

    var body: some View {
        NavigationStack {
            List {
                quickActions
                if store.isOn(.healthKitRead) {
                    Section("Apple Health today") {
                        if healthMetrics.isEmpty {
                            Text("No readings yet.").foregroundStyle(.secondary)
                        }
                        ForEach(healthMetrics.keys.sorted(), id: \.self) { k in
                            LabeledContent(k, value: Fmt.number(healthMetrics[k] ?? 0))
                        }
                    }
                }
                targetsSection
                if store.isOn(.advice) || !openAdvice.isEmpty {
                    adviceSection
                }
            }
            .navigationTitle(Date().formatted(date: .abbreviated, time: .omitted))
            .refreshable { await loadHealth() }
            .task { await loadHealth() }
        }
    }

    private var quickActions: some View {
        Section {
            HStack {
                if store.isOn(.rowing) {
                    Button {
                        Navigation.shared.tab = .row
                    } label: {
                        Label("Start rowing", systemImage: "figure.rower").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if store.isOn(.weights) {
                    Button {
                        if WeightsSession.shared.session == nil { WeightsSession.shared.begin() }
                        Navigation.shared.tab = .weights
                    } label: {
                        Label("Start weights", systemImage: "dumbbell").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: Targets

    private struct Progress: Identifiable {
        let id: String
        let label: String
        let value: Double
        let target: Double
    }

    private var progress: [Progress] {
        let cal = Calendar.current
        let now = Date()
        return store.catalogue.targets.filter(\.enabled).map { t in
            let sessions = store.sessions.filter { s in
                switch t.period {
                case .day: cal.isDate(s.start, inSameDayAs: now)
                case .week: cal.isDate(s.start, equalTo: now, toGranularity: .weekOfYear)
                }
            }
            var value: Double
            switch t.metric {
            case "sessions": value = Double(sessions.count)
            case "energy_kcal":
                value = sessions.reduce(0) { $0 + ($1.summary["energy_kcal_hr"] ?? $1.summary["energy_kcal_console"] ?? 0) }
            default: value = sessions.reduce(0) { $0 + ($1.summary[t.metric] ?? 0) }
            }
            if t.period == .day, let hk = healthMetrics[t.metric] { value = max(value, hk) }
            var label = "\(t.metric) / \(t.period.rawValue)"
            if let z = t.zoneName { label += " (\(z))" }
            return Progress(id: t.id, label: label, value: value, target: t.value)
        }
    }

    private var targetsSection: some View {
        Section("Targets") {
            let items = progress
            if items.isEmpty { Text("No targets enabled.").foregroundStyle(.secondary) }
            ForEach(items) { p in
                VStack(alignment: .leading) {
                    HStack {
                        Text(p.label)
                        Spacer()
                        Text("\(Fmt.number(p.value)) / \(Fmt.number(p.target))").monospacedDigit()
                    }
                    ProgressView(value: min(p.value, max(p.target, 0.0001)), total: max(p.target, 0.0001))
                        .tint(p.value >= p.target ? .green : .accentColor)
                }
            }
        }
    }

    // MARK: Advice

    private var openAdvice: [AdviceNote] {
        store.advice.filter { $0.status == .open }.sorted { $0.date > $1.date }
    }

    private var adviceSection: some View {
        Section("Advice") {
            if openAdvice.isEmpty { Text("No open advice.").foregroundStyle(.secondary) }
            ForEach(openAdvice) { note in
                VStack(alignment: .leading, spacing: 6) {
                    Text(note.title).font(.headline)
                    Text(note.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    Text(note.body).font(.callout).lineLimit(8)
                    HStack {
                        Button("Done") { store.setAdviceStatus(id: note.id, status: .done) }
                            .buttonStyle(.borderedProminent)
                        Button("Reject", role: .destructive) { store.setAdviceStatus(id: note.id, status: .rejected) }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func loadHealth() async {
        guard store.isOn(.healthKitRead) else { return }
        healthMetrics = await HealthKitService.shared.readDailyMetrics(for: Date())
    }
}
