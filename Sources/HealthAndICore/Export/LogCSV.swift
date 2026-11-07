import Foundation

/// Flat spreadsheet table: one row per set, plus one summary row per rowing session.
public enum LogCSV {
    public static let summaryColumns = [
        "duration_s", "distance_m", "avg_hr", "max_hr", "minutes_in_zone", "avg_stroke_rate",
        "avg_pace", "energy_kcal_hr", "energy_kcal_console",
    ]
    public static let columns = [
        "session_id", "date", "type", "exercise", "side", "reps", "seconds", "meters", "load_kg",
        "rir", "rpe", "rest_s", "tags", "notes", "exercise_id", "row_kind",
    ] + summaryColumns

    public static func render(sessions: [Session], catalogue: Catalogue) -> String {
        let tz = ExportFormat.timeZone(catalogue)
        var rows: [[String]] = [columns]
        for session in sessions.sorted(by: { $0.start < $1.start }) {
            let date = ExportFormat.string(session.start, "yyyy-MM-dd HH:mm", tz)
            for set in session.sets {
                var row = [
                    session.id, date, session.type,
                    ExportFormat.exerciseName(set.exerciseId, catalogue),
                    set.side.rawValue,
                    set.reps.map(String.init) ?? "",
                    opt(set.seconds), opt(set.meters),
                    opt(ExportFormat.loadKg(set.load, catalogue)),
                    opt(set.rir), opt(set.rpe), opt(set.restBeforeSeconds),
                    set.variantTags.joined(separator: ";"),
                    set.notes ?? "",
                    set.exerciseId, "set",
                ]
                row += Array(repeating: "", count: summaryColumns.count)
                rows.append(row)
            }
            if isRowing(session) {
                let duration = session.end.map { $0.timeIntervalSince(session.start) }
                var row = [
                    session.id, date, session.type, "", "", "",
                    opt(duration), opt(session.summary["distance_m"]), "", "", "", "", "",
                    session.notes ?? "", "", "session_summary",
                ]
                row += summaryColumns.map { $0 == "duration_s" ? opt(duration) : opt(session.summary[$0]) }
                rows.append(row)
            }
        }
        return rows.map { $0.map(quote).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func isRowing(_ s: Session) -> Bool {
        s.type.lowercased() == "rowing" || (s.sets.isEmpty && !s.summary.isEmpty)
    }

    static func opt(_ v: Double?) -> String { v.map { ExportFormat.num($0, places: 3) } ?? "" }

    /// RFC 4180: quote when the field holds a comma, quote, CR or LF; double embedded quotes.
    public static func quote(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
