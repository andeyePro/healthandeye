import SwiftUI
import HealthAndICore

struct LogView: View {
    private var store: StoreController { StoreController.shared }

    private var grouped: [(day: String, sessions: [Session])] {
        let sorted = store.sessions.sorted { $0.start > $1.start }
        var out: [(String, [Session])] = []
        for s in sorted {
            let day = s.start.formatted(date: .complete, time: .omitted)
            if out.last?.0 == day { out[out.count - 1].1.append(s) } else { out.append((day, [s])) }
        }
        return out.map { (day: $0.0, sessions: $0.1) }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.sessions.isEmpty {
                    Text("No sessions yet.").foregroundStyle(.secondary)
                }
                ForEach(grouped, id: \.day) { group in
                    Section(group.day) {
                        ForEach(group.sessions) { s in
                            NavigationLink {
                                SessionDetailView(session: s)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text("\(s.start.formatted(date: .omitted, time: .shortened))  \(s.type)")
                                    Text(Fmt.summaryLine(s)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Log")
        }
    }
}

struct SessionDetailView: View {
    let session: Session
    private var store: StoreController { StoreController.shared }

    var body: some View {
        List {
            if !session.sets.isEmpty {
                Section("Sets") {
                    ForEach(session.sets) { set in
                        SetRow(set: set)
                    }
                }
            }
            Section("Markdown") {
                ScrollView(.horizontal) {
                    Text(SessionMarkdown.render(session, catalogue: store.catalogue))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .navigationTitle(session.type.capitalized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SetRow: View {
    let set: SetEntry
    private var store: StoreController { StoreController.shared }

    var body: some View {
        let cat = store.catalogue
        let name = cat.exercise(id: set.exerciseId)?.name ?? set.exerciseId
        var bits: [String] = []
        if set.side != .both { bits.append(set.side == .left ? "L" : "R") }
        if let r = set.reps { bits.append("\(r) reps") }
        if let s = set.seconds { bits.append(Fmt.duration(s)) }
        if let m = set.meters { bits.append("\(Fmt.number(m)) m") }
        if let load = set.load, let kg = LoadBuilder.totalKg(load, catalogue: cat) { bits.append("\(Fmt.number(kg, digits: 2)) kg") }
        if let rir = set.rir { bits.append("RIR \(Fmt.number(rir))") }
        if let rpe = set.rpe { bits.append("RPE \(Fmt.number(rpe))") }
        if let rest = set.restBeforeSeconds { bits.append("rest \(Fmt.duration(rest))\(set.restInterrupted == true ? "*" : "")") }
        return VStack(alignment: .leading) {
            Text(name)
            Text(bits.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            if !set.variantTags.isEmpty {
                Text(set.variantTags.joined(separator: ", ")).font(.caption2).foregroundStyle(.tint)
            }
            if let n = set.notes { Text(n).font(.caption2) }
        }
    }
}
