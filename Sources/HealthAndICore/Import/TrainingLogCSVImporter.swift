import Foundation

/// Imports a Training Log style CSV (e.g. a Google Sheet export). Header-driven and tolerant:
/// columns are matched by name, case and spacing ignored; rows that cannot be read become warnings.
public struct TrainingLogCSVImporter: Sendable {
    /// Field -> accepted header names, `|`-separated.
    public static let defaults: [String: String] = [
        "date": "date|day",
        "exercise": "exercise|movement",
        "side": "side",
        "reps": "reps",
        "load": "load|weight|kg",
        "rir": "rir",
        "rpe": "rpe",
        "notes": "notes",
        "set": "set",
    ]

    public var columnMap: [String: String]

    public init(columnMap: [String: String] = TrainingLogCSVImporter.defaults) {
        self.columnMap = columnMap
    }

    public func parse(csv: String, catalogue: Catalogue) -> (sessions: [Session], newExercises: [Exercise], warnings: [String]) {
        var warnings: [String] = []
        let rows = Self.parseRows(csv)
        guard let header = rows.first else { return ([], [], ["CSV is empty."]) }
        let columns = resolveColumns(header)
        for required in ["date", "exercise"] where columns[required] == nil {
            warnings.append("No \(required) column found (accepted headers: \(columnMap[required] ?? required)).")
        }
        guard columns["date"] != nil, columns["exercise"] != nil else { return ([], [], warnings) }

        let tz = ExportFormat.timeZone(catalogue)
        var exercises = catalogue.exercises
        var newExercises: [Exercise] = []
        var sideUsed: [String: Bool] = [:]
        var byDate: [String: [SetEntry]] = [:]
        var lastDate: String?

        for (index, row) in rows.enumerated().dropFirst() {
            let line = index + 1
            func field(_ name: String) -> String {
                guard let i = columns[name], i < row.count else { return "" }
                return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }

            let dateText = field("date")
            let day: String
            if dateText.isEmpty {
                // Logs often fill the date only on the first row of a day.
                guard let lastDate else { warnings.append("Row \(line): no date."); continue }
                day = lastDate
            } else if let parsed = Self.parseDate(dateText) {
                day = parsed
            } else {
                warnings.append("Row \(line): unreadable date \"\(dateText)\"."); continue
            }
            lastDate = day

            let exerciseText = field("exercise")
            guard !exerciseText.isEmpty else { warnings.append("Row \(line): no exercise."); continue }

            var problems: [String] = []
            func number(_ name: String) -> Double? {
                let text = field(name)
                guard !text.isEmpty else { return nil }
                guard let v = Self.parseNumber(text) else { problems.append("\(name) \"\(text)\""); return nil }
                return v
            }
            let reps = number("reps")
            let kg = number("load")
            let rir = number("rir")
            let rpe = number("rpe")
            let side = Self.parseSide(field("side"))
            if side == nil { problems.append("side \"\(field("side"))\"") }
            guard problems.isEmpty else {
                warnings.append("Row \(line): unreadable \(problems.joined(separator: ", ")).")
                continue
            }

            let exId: String
            if let ex = exercises.first(where: { Self.matches($0, exerciseText) }) {
                exId = ex.id
            } else {
                let ex = Exercise(id: Self.uniqueId("ex-" + Self.slug(exerciseText), taken: Set(exercises.map(\.id))),
                                  name: exerciseText)
                exercises.append(ex)
                newExercises.append(ex)
                exId = ex.id
            }
            if side != .both { sideUsed[exId] = true }

            let notes = field("notes")
            let set = SetEntry(id: "", exerciseId: exId, side: side!, reps: reps.map { Int($0.rounded()) },
                               load: kg.map { Load(fixedKg: $0) }, rir: rir, rpe: rpe,
                               notes: notes.isEmpty ? nil : notes)
            byDate[day, default: []].append(set)
        }

        for i in newExercises.indices where sideUsed[newExercises[i].id] == true { newExercises[i].unilateral = true }

        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.timeZone = tz
        iso.dateFormat = "yyyy-MM-dd"
        let sessions = byDate.keys.sorted().compactMap { day -> Session? in
            guard let start = iso.date(from: day) else { return nil }
            let id = "\(day)-0000-weights"
            let sets = byDate[day]!.enumerated().map { n, s -> SetEntry in
                var s = s
                s.id = "\(id)-s\(n + 1)"
                return s
            }
            return Session(id: id, start: start, type: "weights", notes: "Imported from training log CSV.", sets: sets)
        }
        return (sessions, newExercises, warnings)
    }

    func resolveColumns(_ header: [String]) -> [String: Int] {
        let normalized = header.map(Self.normalize)
        var out: [String: Int] = [:]
        for (field, aliases) in columnMap {
            let names = aliases.split(separator: "|").map { Self.normalize(String($0)) }
            if let i = normalized.firstIndex(where: { names.contains($0) }) {
                out[field] = i
            } else if let i = normalized.firstIndex(where: { h in names.contains { h.hasPrefix($0) } }) {
                // "Load (kg)" or "Reps done" still match "load" / "reps".
                out[field] = i
            }
        }
        return out
    }

    static func normalize(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    static func slug(_ s: String) -> String {
        var out = ""
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber, ch.isASCII { out.append(ch) } else if !out.hasSuffix("-") { out.append("-") }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "exercise" : trimmed
    }

    static func uniqueId(_ base: String, taken: Set<String>) -> String {
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    static func matches(_ ex: Exercise, _ text: String) -> Bool {
        let n = normalize(text)
        return normalize(ex.name) == n || ex.id == text || ex.id == "ex-" + slug(text)
    }

    /// dd/mm/yyyy (also d/m/yy, dots or dashes) or ISO yyyy-mm-dd, optionally followed by a time. Returns YYYY-MM-DD.
    static func parseDate(_ text: String) -> String? {
        let datePart = text.split(whereSeparator: { $0 == " " || $0 == "T" }).first.map(String.init) ?? text
        let parts = datePart.split(whereSeparator: { "/.-".contains($0) }).map(String.init)
        guard parts.count == 3, let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]) else { return nil }
        let (y, m, d): (Int, Int, Int)
        if parts[0].count == 4 {
            (y, m, d) = (a, b, c)
        } else {
            (y, m, d) = (parts[2].count == 2 ? 2000 + c : c, b, a)
        }
        guard (1...12).contains(m), (1...31).contains(d), (1900...2999).contains(y) else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func parseNumber(_ text: String) -> Double? {
        var t = text.lowercased().replacingOccurrences(of: "kg", with: "").trimmingCharacters(in: .whitespaces)
        if !t.contains(".") { t = t.replacingOccurrences(of: ",", with: ".") }
        return Double(t)
    }

    static func parseSide(_ text: String) -> Side? {
        switch normalize(text) {
        case "", "both", "b", "bilateral", "lr": return .both
        case "l", "left": return .left
        case "r", "right": return .right
        default: return nil
        }
    }

    /// RFC 4180 rows: quoted fields may contain commas, doubled quotes and line breaks.
    static func parseRows(_ csv: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(csv.unicodeScalars).makeIterator()
        var pending: Unicode.Scalar? = nil
        func next() -> Unicode.Scalar? {
            if let p = pending { pending = nil; return p }
            return chars.next()
        }
        while let c = next() {
            if inQuotes {
                if c == "\"" {
                    if let n = next() {
                        if n == "\"" { field.unicodeScalars.append("\"") } else { inQuotes = false; pending = n }
                    } else { inQuotes = false }
                } else {
                    field.unicodeScalars.append(c)
                }
                continue
            }
            switch c {
            case "\"": inQuotes = true
            case ",": row.append(field); field = ""
            case "\r", "\n":
                if c == "\r", let n = next(), n != "\n" { pending = n }
                row.append(field); field = ""
                rows.append(row); row = []
            default: field.unicodeScalars.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        if let first = rows.first?.first, first.hasPrefix("\u{FEFF}") { rows[0][0] = String(first.dropFirst()) }
        return rows
    }
}
