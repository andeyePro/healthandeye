import Foundation

/// Human-readable differences between two catalogues, one line per change:
/// `+ equipment eq-x (Name)`, `- exercise ex-y (Name)`, `~ equipment eq-x: limits, notes`, `~ settings: hud_tiles`.
public struct CatalogueDiff: Equatable, Sendable {
    public var lines: [String]
    public var isEmpty: Bool { lines.isEmpty }

    public init(lines: [String] = []) {
        self.lines = lines
    }

    public init(old: Catalogue, new: Catalogue) {
        var lines: [String] = []
        lines += Self.single("profile", old.profile, new.profile)
        lines += Self.list("equipment", old.equipment, new.equipment, id: \.id, name: \.name)
        lines += Self.list("exercise", old.exercises, new.exercises, id: \.id, name: \.name)
        lines += Self.list("zone set", old.zoneSets, new.zoneSets, id: \.id, name: \.name)
        lines += Self.list("target", old.targets, new.targets, id: \.id, name: \.metric)
        lines += Self.list("food", old.foods, new.foods, id: \.id, name: \.name)
        lines += Self.single("settings", old.settings, new.settings)
        self.lines = lines
    }

    static func single<T: Encodable & Equatable>(_ label: String, _ a: T, _ b: T) -> [String] {
        guard a != b else { return [] }
        return ["~ \(label): \(changedKeys(a, b).joined(separator: ", "))"]
    }

    static func list<T: Encodable & Equatable>(_ label: String, _ old: [T], _ new: [T],
                                               id: KeyPath<T, String>, name: KeyPath<T, String>) -> [String] {
        var out: [String] = []
        let oldById = Dictionary(old.map { ($0[keyPath: id], $0) }, uniquingKeysWith: { a, _ in a })
        let newIds = Set(new.map { $0[keyPath: id] })
        for item in new {
            let key = item[keyPath: id]
            if let before = oldById[key] {
                if before != item {
                    out.append("~ \(label) \(key): \(changedKeys(before, item).joined(separator: ", "))")
                }
            } else {
                out.append("+ \(label) \(key) (\(item[keyPath: name]))")
            }
        }
        for item in old where !newIds.contains(item[keyPath: id]) {
            out.append("- \(label) \(item[keyPath: id]) (\(item[keyPath: name]))")
        }
        return out
    }

    static func changedKeys<T: Encodable>(_ a: T, _ b: T) -> [String] {
        let da = object(a), db = object(b)
        let keys = Set(da.keys).union(db.keys)
        let changed = keys.filter { da[$0] != db[$0] }.sorted()
        return changed.isEmpty ? ["changed"] : changed
    }

    static func object<T: Encodable>(_ v: T) -> [String: Data] {
        guard let data = try? JSONCoding.encode(v),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: Data] = [:]
        for (k, value) in obj {
            out[k] = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        }
        return out
    }
}
