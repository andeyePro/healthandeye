import Foundation

/// Rolling summary for Claude: last 7 / 28 days against targets, per-exercise trends, flags, open advice.
public enum Digest {
    static let day: TimeInterval = 86_400
    static let noSessionFlagDays = 5
    static let missedWeeksFlag = 3

    public static func render(catalogue: Catalogue, sessions: [Session], days: [DaySnapshot],
                              advice: [AdviceNote], now: Date) -> String {
        let tz = ExportFormat.timeZone(catalogue)
        var lines = ["# Health&I digest", "",
                     "Generated \(ExportFormat.dateTime(now, tz)) (\(tz.identifier)). Windows are the 7 and 28 days ending now.",
                     ""]

        lines.append("## Targets")
        lines.append("")
        let targets = catalogue.targets.filter(\.enabled)
        if targets.isEmpty {
            lines.append("No enabled targets.")
        } else {
            lines.append("| Target | Metric | Goal | Last 7 days | Last 28 days | 7-day status |")
            lines.append("|---|---|---|---|---|---|")
            for t in targets {
                let w7 = value(t, sessions: sessions, days: days, from: now - 7 * day, to: now, tz: tz)
                let w28 = value(t, sessions: sessions, days: days, from: now - 28 * day, to: now, tz: tz)
                let status = w7.map { $0 >= t.value ? "met" : "missed" } ?? "no data"
                let cells = [t.id, metricLabel(t), "\(ExportFormat.num(t.value)) per \(t.period.rawValue)",
                             w7.map { ExportFormat.num($0, places: 1) } ?? "no data",
                             w28.map { ExportFormat.num($0, places: 1) } ?? "no data", status]
                lines.append("| " + cells.map(ExportFormat.cell).joined(separator: " | ") + " |")
            }
            lines.append("")
            lines.append("Weekly targets show the total for the last 7 days and the weekly average over 28 days; daily targets show the mean per logged day.")
        }

        lines.append("")
        lines.append("## Exercises (last 28 days)")
        lines.append("")
        lines.append(contentsOf: exerciseLines(catalogue: catalogue, sessions: sessions, now: now))

        lines.append("")
        lines.append("## Flags")
        lines.append("")
        let flags = self.flags(catalogue: catalogue, sessions: sessions, days: days, now: now, tz: tz)
        lines.append(contentsOf: flags.isEmpty ? ["None."] : flags.map { "- \($0)" })

        lines.append("")
        lines.append("## Open advice")
        lines.append("")
        let open = advice.filter { $0.status == .open }.sorted { $0.date < $1.date }
        if open.isEmpty {
            lines.append("None.")
        } else {
            for a in open {
                lines.append("- \(ExportFormat.day(a.date, tz)) \(a.title) (`advice/\(a.id).md`)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func metricLabel(_ t: Target) -> String {
        guard t.metric == "minutes_in_zone", let zone = t.zoneName else { return t.metric }
        return "\(t.metric) (\(zone))"
    }

    /// Weekly target: total over the window scaled to one week. Daily target: mean per day with data.
    /// nil when the window holds no data for a day-snapshot metric.
    static func value(_ t: Target, sessions: [Session], days: [DaySnapshot], from: Date, to: Date, tz: TimeZone) -> Double? {
        let weeks = to.timeIntervalSince(from) / (7 * day)
        let windowDays = max(1, to.timeIntervalSince(from) / day)
        let inWindow = sessions.filter { $0.start >= from && $0.start < to }
        if isSessionMetric(t.metric, sessions: sessions, days: days) {
            let total = inWindow.compactMap { $0.summary[t.metric] }.reduce(0, +)
            return t.period == .week ? total / weeks : total / windowDays
        }
        let fromDay = ExportFormat.day(from, tz), toDay = ExportFormat.day(to, tz)
        let values = days.filter { $0.date > fromDay && $0.date <= toDay }
            .compactMap { $0.totals[t.metric] ?? $0.metrics[t.metric] }
        guard !values.isEmpty else { return nil }
        let total = values.reduce(0, +)
        return t.period == .week ? total / weeks : total / Double(values.count)
    }

    static func isSessionMetric(_ metric: String, sessions: [Session], days: [DaySnapshot]) -> Bool {
        if metric == "minutes_in_zone" { return true }
        let inDays = days.contains { $0.totals[metric] != nil || $0.metrics[metric] != nil }
        return !inDays && sessions.contains { $0.summary[metric] != nil }
    }

    struct Best { var kg: Double?; var reps: Int?; var score: Double }

    static func exerciseLines(catalogue: Catalogue, sessions: [Session], now: Date) -> [String] {
        let recent = sessions.filter { $0.start >= now - 28 * day && $0.start <= now }
        var ids: [String] = []
        for s in recent.sorted(by: { $0.start < $1.start }) {
            for set in s.sets where !ids.contains(set.exerciseId) { ids.append(set.exerciseId) }
        }
        guard !ids.isEmpty else { return ["No sets logged."] }
        var lines = ["| Exercise | Best set (28 d) | Best last 7 d | Best prior 21 d | Trend |", "|---|---|---|---|---|"]
        for id in ids {
            let all = best(id, recent, catalogue)
            let last7 = best(id, recent.filter { $0.start >= now - 7 * day }, catalogue)
            let prior = best(id, recent.filter { $0.start < now - 7 * day }, catalogue)
            let arrow: String
            if let a = last7, let b = prior {
                arrow = a.score > b.score * 1.02 ? "↑" : (a.score < b.score * 0.98 ? "↓" : "→")
            } else {
                arrow = "–"
            }
            let cells = [ExportFormat.exerciseName(id, catalogue), describe(all), describe(last7), describe(prior), arrow]
            lines.append("| " + cells.map(ExportFormat.cell).joined(separator: " | ") + " |")
        }
        lines.append("")
        lines.append("Best set = highest load × reps (reps alone when unloaded). Trend compares the last 7 days with the 21 days before: ↑ up >2%, ↓ down >2%, → flat, – not enough data.")
        return lines
    }

    static func best(_ id: String, _ sessions: [Session], _ catalogue: Catalogue) -> Best? {
        var result: Best?
        for s in sessions {
            for set in s.sets where set.exerciseId == id {
                let kg = ExportFormat.loadKg(set.load, catalogue)
                let amount = Double(set.reps ?? 0) + (set.reps == nil ? (set.seconds ?? set.meters ?? 0) : 0)
                let score = (kg ?? 1) * amount
                if result == nil || score > result!.score { result = Best(kg: kg, reps: set.reps, score: score) }
            }
        }
        return result
    }

    static func describe(_ b: Best?) -> String {
        guard let b else { return "" }
        switch (b.kg, b.reps) {
        case let (kg?, reps?): return "\(ExportFormat.num(kg)) kg × \(reps)"
        case let (nil, reps?): return "\(reps) reps"
        case let (kg?, nil): return "\(ExportFormat.num(kg)) kg, score \(ExportFormat.num(b.score))"
        default: return "score \(ExportFormat.num(b.score))"
        }
    }

    static func flags(catalogue: Catalogue, sessions: [Session], days: [DaySnapshot], now: Date, tz: TimeZone) -> [String] {
        var out: [String] = []
        let past = sessions.filter { $0.start <= now }
        if let last = past.map(\.start).max() {
            let gap = Int(now.timeIntervalSince(last) / day)
            if gap >= noSessionFlagDays {
                out.append("No session for \(gap) days (last \(ExportFormat.day(last, tz))).")
            }
        } else {
            out.append("No sessions logged yet.")
        }
        for t in catalogue.targets where t.enabled {
            var missed = 0
            for w in 0..<missedWeeksFlag {
                let to = now - Double(w) * 7 * day
                guard let v = value(t, sessions: sessions, days: days, from: to - 7 * day, to: to, tz: tz), v < t.value else { break }
                missed += 1
            }
            if missed == missedWeeksFlag {
                out.append("Target `\(t.id)` (\(metricLabel(t)) \(ExportFormat.num(t.value)) per \(t.period.rawValue)) missed \(missedWeeksFlag) weeks running.")
            }
        }
        return out
    }
}
