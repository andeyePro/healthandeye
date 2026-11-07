import SwiftUI
import HealthAndICore

struct RecentView: View {
    private var store: StoreController { .shared }

    var body: some View {
        let recent = Array(store.sessions.sorted { $0.start > $1.start }.prefix(10))
        List {
            if recent.isEmpty {
                Text("No sessions yet").foregroundStyle(.secondary)
            }
            ForEach(recent) { session in
                Text(Self.line(for: session))
                    .font(.footnote)
                    .lineLimit(1)
            }
        }
        .navigationTitle("Recent")
    }

    static func line(for session: Session) -> String {
        let date = session.start.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        var parts = [date, session.type]
        if let end = session.end {
            parts.append("\(Int(end.timeIntervalSince(session.start) / 60)) min")
        }
        if !session.sets.isEmpty {
            parts.append("\(session.sets.count) sets")
        }
        if let d = session.summary["distance_m"] {
            parts.append("\(Int(d)) m")
        }
        return parts.joined(separator: " · ")
    }
}
