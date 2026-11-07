import Foundation

/// Relative paths of every file in the store / export folder.
public enum StoreLayout {
    public static let readme = "README.md"
    public static let schema = "schema.md"
    public static let digest = "digest.md"
    public static let logCSV = "log.csv"

    public static let catalogueDir = "catalogue"
    public static let profile = "catalogue/profile.json"
    public static let equipment = "catalogue/equipment.json"
    public static let exercises = "catalogue/exercises.json"
    public static let zones = "catalogue/zones.json"
    public static let targets = "catalogue/targets.json"
    public static let foods = "catalogue/foods.json"
    public static let settings = "catalogue/settings.json"
    public static let catalogueFiles = [profile, equipment, exercises, zones, targets, foods, settings]

    public static let sessionsDir = "sessions"
    public static let dailyDir = "daily"
    public static let bodyMeasures = "body/measures.json"
    public static let adviceDir = "advice"
    public static let adviceStatus = "advice/status.json"

    /// `YYYY-MM-DD-HHMM-<type>` in the given time zone.
    public static func sessionStem(_ session: Session, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd-HHmm"
        let type = slug(session.type.isEmpty ? "other" : session.type)
        return "\(f.string(from: session.start))-\(type)"
    }

    /// `sessions/YYYY/<stem>.json`.
    public static func sessionPath(_ session: Session, timeZone: TimeZone = .current) -> String {
        let stem = sessionStem(session, timeZone: timeZone)
        return "\(sessionsDir)/\(stem.prefix(4))/\(stem).json"
    }

    /// `daily/YYYY/YYYY-MM-DD.json`.
    public static func dayPath(_ date: String) -> String {
        "\(dailyDir)/\(date.prefix(4))/\(date).json"
    }

    static func slug(_ s: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-_")
        let mapped = s.lowercased().map { allowed.contains($0) ? $0 : "-" }
        return String(mapped)
    }
}
