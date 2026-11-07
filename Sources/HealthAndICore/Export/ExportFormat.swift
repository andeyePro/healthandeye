import Foundation

/// Shared formatting for the Claude-readable export files.
enum ExportFormat {
    static func timeZone(_ catalogue: Catalogue) -> TimeZone {
        if let id = catalogue.profile.timeZone, let tz = TimeZone(identifier: id) { return tz }
        return TimeZone(identifier: "UTC")!
    }

    static func calendar(_ tz: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal
    }

    static func string(_ date: Date, _ format: String, _ tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = format
        return f.string(from: date)
    }

    static func day(_ date: Date, _ tz: TimeZone) -> String { string(date, "yyyy-MM-dd", tz) }
    static func dateTime(_ date: Date, _ tz: TimeZone) -> String { string(date, "yyyy-MM-dd HH:mm", tz) }

    /// Plain decimal with at most `places` decimals and no trailing zeros, "." separator always.
    static func num(_ value: Double, places: Int = 2) -> String {
        guard value.isFinite else { return "" }
        var s = String(format: "%.\(places)f", value)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s == "-0" ? "0" : s
    }

    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func cell(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    static func exerciseName(_ id: String, _ catalogue: Catalogue) -> String {
        catalogue.exercises.first { $0.id == id }?.name ?? id
    }

    static func loadKg(_ load: Load?, _ catalogue: Catalogue) -> Double? {
        guard let load else { return nil }
        return LoadBuilder.totalKg(load, catalogue: catalogue)
    }

    /// "11.53 kg per hand (1× Bar 1.47 kg + 2× Plate 5.03 kg)"; breakdown omitted for fixed loads.
    static func loadDescription(_ load: Load?, _ catalogue: Catalogue) -> String {
        guard let load else { return "" }
        var out = ""
        if let total = LoadBuilder.totalKg(load, catalogue: catalogue) {
            out = "\(num(total)) kg"
            if load.perHand { out += " per hand" }
        }
        let parts = LoadBuilder.breakdown(load, catalogue: catalogue)
        if !parts.isEmpty {
            let text = parts.map { "\($0.count)× \($0.name) \(num($0.kg)) kg" }.joined(separator: " + ")
            out += out.isEmpty ? text : " (\(text))"
        }
        if let label = load.label, !label.isEmpty { out += out.isEmpty ? label : " [\(label)]" }
        return out
    }

    static let metricUnits: [String: String] = [
        "heart_rate": "bpm", "stroke_rate": "spm", "pace_s_per_500m": "s/500m", "distance_m": "m",
        "resistance": "level", "power_w": "W", "energy_kcal": "kcal", "stroke_count": "strokes",
        "avg_hr": "bpm", "max_hr": "bpm", "minutes_in_zone": "min", "avg_stroke_rate": "spm",
        "avg_pace": "s/500m", "energy_kcal_hr": "kcal", "energy_kcal_console": "kcal",
    ]
}
