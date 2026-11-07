import Foundation

/// Renders one session as readable Markdown: the `.md` sibling of each session JSON file.
public enum SessionMarkdown {
    public static func render(_ session: Session, catalogue: Catalogue) -> String {
        let tz = ExportFormat.timeZone(catalogue)
        var lines: [String] = []
        let title = session.type.prefix(1).uppercased() + session.type.dropFirst()
        lines.append("# \(title) session \(ExportFormat.dateTime(session.start, tz))")
        lines.append("")
        lines.append("- Session id: `\(session.id)`")
        lines.append("- Date: \(ExportFormat.dateTime(session.start, tz)) (\(tz.identifier))")
        lines.append("- Type: \(session.type)")
        if let end = session.end {
            lines.append("- Duration: \(ExportFormat.clock(end.timeIntervalSince(session.start))) (\(ExportFormat.num(end.timeIntervalSince(session.start) / 60, places: 1)) min)")
        } else {
            lines.append("- Duration: unknown (no end time)")
        }
        lines.append("- HR source: \(session.hrSource?.rawValue ?? "none")")
        if !session.equipmentIds.isEmpty {
            let names = session.equipmentIds.map { id in
                catalogue.equipment.first { $0.id == id }.map { "\($0.name) (`\(id)`)" } ?? "`\(id)`"
            }
            lines.append("- Equipment: \(names.joined(separator: ", "))")
        }
        if let wid = session.healthKitWorkoutId { lines.append("- HealthKit workout: \(wid)") }
        if let notes = session.notes, !notes.isEmpty { lines.append("- Notes: \(ExportFormat.cell(notes))") }

        if !session.sets.isEmpty {
            lines.append("")
            lines.append("## Sets")
            lines.append(contentsOf: setsSection(session, catalogue: catalogue))
        }
        if !session.summary.isEmpty {
            lines.append("")
            lines.append("## Summary")
            if let rowing = rowingLine(session) { lines.append(rowing) ; lines.append("") }
            for key in session.summary.keys.sorted() {
                let unit = ExportFormat.metricUnits[key].map { " \($0)" } ?? ""
                lines.append("- \(key): \(ExportFormat.num(session.summary[key]!))\(unit)")
            }
        }
        if !session.intervals.isEmpty {
            lines.append("")
            lines.append(contentsOf: intervalSection(session.intervals))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func rowingLine(_ session: Session) -> String? {
        let s = session.summary
        guard session.type == "rowing" || s["distance_m"] != nil else { return nil }
        var parts: [String] = []
        if let d = s["distance_m"] { parts.append("\(ExportFormat.num(d, places: 0)) m") }
        if let end = session.end { parts.append("in \(ExportFormat.clock(end.timeIntervalSince(session.start)))") }
        if let p = s["avg_pace"] { parts.append("avg pace \(ExportFormat.clock(p))/500m") }
        if let r = s["avg_stroke_rate"] { parts.append("\(ExportFormat.num(r, places: 1)) spm") }
        if let hr = s["avg_hr"] { parts.append("avg HR \(ExportFormat.num(hr, places: 0)) bpm") }
        if let hr = s["max_hr"] { parts.append("max HR \(ExportFormat.num(hr, places: 0)) bpm") }
        if let z = s["minutes_in_zone"] { parts.append("\(ExportFormat.num(z, places: 1)) min in zone") }
        if let e = s["energy_kcal_hr"] { parts.append("\(ExportFormat.num(e, places: 0)) kcal (HR estimate)") }
        if let e = s["energy_kcal_console"] { parts.append("\(ExportFormat.num(e, places: 0)) kcal (console)") }
        guard !parts.isEmpty else { return nil }
        return "Rowing: " + parts.joined(separator: ", ")
    }

    static func setsSection(_ session: Session, catalogue: Catalogue) -> [String] {
        var order: [String] = []
        var grouped: [String: [SetEntry]] = [:]
        for set in session.sets {
            if grouped[set.exerciseId] == nil { order.append(set.exerciseId) }
            grouped[set.exerciseId, default: []].append(set)
        }
        var lines: [String] = []
        for exId in order {
            lines.append("")
            lines.append("### \(ExportFormat.exerciseName(exId, catalogue)) (`\(exId)`)")
            lines.append("")
            lines.append("| # | Side | Amount | Load | Effort | Rest before | Tags | Notes |")
            lines.append("|---|---|---|---|---|---|---|---|")
            for (i, set) in grouped[exId]!.enumerated() {
                let cells = [
                    "\(i + 1)",
                    set.side.rawValue,
                    amount(set),
                    ExportFormat.loadDescription(set.load, catalogue),
                    effort(set),
                    rest(set),
                    set.variantTags.joined(separator: ", "),
                    set.notes ?? "",
                ].map(ExportFormat.cell)
                lines.append("| " + cells.joined(separator: " | ") + " |")
            }
        }
        return lines
    }

    static func amount(_ set: SetEntry) -> String {
        var parts: [String] = []
        if let r = set.reps { parts.append("\(r) reps") }
        if let s = set.seconds { parts.append("\(ExportFormat.num(s, places: 1)) s") }
        if let m = set.meters { parts.append("\(ExportFormat.num(m, places: 1)) m") }
        return parts.joined(separator: ", ")
    }

    static func effort(_ set: SetEntry) -> String {
        var parts: [String] = []
        if let r = set.rir { parts.append("RIR \(ExportFormat.num(r, places: 1))") }
        if let r = set.rpe { parts.append("RPE \(ExportFormat.num(r, places: 1))") }
        return parts.joined(separator: ", ")
    }

    static func rest(_ set: SetEntry) -> String {
        guard let r = set.restBeforeSeconds else { return "" }
        return "\(ExportFormat.num(r, places: 0)) s" + (set.restInterrupted == true ? " (interrupted)" : "")
    }

    /// Per-minute means, one column per series, so a long session stays a short table.
    static func intervalSection(_ series: [IntervalSeries]) -> [String] {
        var buckets: [[Int: (sum: Double, n: Int)]] = []
        var maxMinute = -1
        for s in series {
            var b: [Int: (sum: Double, n: Int)] = [:]
            for sample in s.samples where sample.v.isFinite && sample.t >= 0 {
                let m = Int(sample.t / 60)
                let cur = b[m] ?? (0, 0)
                b[m] = (cur.sum + sample.v, cur.n + 1)
                maxMinute = max(maxMinute, m)
            }
            buckets.append(b)
        }
        var lines = ["## Intervals (per-minute means)", ""]
        guard maxMinute >= 0 else {
            lines.append("No samples recorded.")
            return lines
        }
        let header = series.map { "\($0.metric) (\($0.unit), \($0.source.rawValue))" }
        lines.append("| Minute | " + header.map(ExportFormat.cell).joined(separator: " | ") + " |")
        lines.append("|---|" + String(repeating: "---|", count: series.count))
        for m in 0...maxMinute {
            let cells = buckets.map { b -> String in
                guard let v = b[m], v.n > 0 else { return "" }
                return ExportFormat.num(v.sum / Double(v.n), places: 1)
            }
            if cells.allSatisfy({ $0.isEmpty }) { continue }
            lines.append("| \(m) | " + cells.joined(separator: " | ") + " |")
        }
        return lines
    }
}
