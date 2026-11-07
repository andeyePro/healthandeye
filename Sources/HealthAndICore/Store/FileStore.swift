import Foundation

/// Reads and writes the store folder (see `StoreLayout`). The folder is also the export Claude reads.
///
/// Rendering of Markdown/derived files is injected so the store depends only on the model:
/// the app wires `markdownRenderer = SessionMarkdown.render` and a `derivedRenderer` that returns
/// README.md, schema.md, digest.md and log.csv contents.
public final class FileStore: @unchecked Sendable {
    public typealias MarkdownRenderer = @Sendable (Session, Catalogue) -> String
    /// Returns relative path -> file contents.
    public typealias DerivedRenderer = @Sendable (Catalogue, [Session]) -> [String: String]

    public let root: URL
    /// Session filenames use local time of the session in this zone.
    public let timeZone: TimeZone
    public let markdownRenderer: MarkdownRenderer?
    public let derivedRenderer: DerivedRenderer?

    private let lock = NSLock()
    private var catalogueSnapshot: [String: Data]?
    private var lastCatalogue: Catalogue?
    private let fm = FileManager.default

    public init(root: URL, timeZone: TimeZone = .current, markdownRenderer: MarkdownRenderer? = nil,
                derivedRenderer: DerivedRenderer? = nil) {
        self.root = root
        self.timeZone = timeZone
        self.markdownRenderer = markdownRenderer
        self.derivedRenderer = derivedRenderer
    }

    public func url(_ relative: String) -> URL {
        root.appendingPathComponent(relative)
    }

    // MARK: Catalogue

    public func loadCatalogue() throws -> Catalogue {
        let (catalogue, snapshot) = try readCatalogue()
        lock.withLock {
            catalogueSnapshot = snapshot
            lastCatalogue = catalogue
        }
        return catalogue
    }

    public func saveCatalogue(_ catalogue: Catalogue) throws {
        try write(catalogue.profile, to: StoreLayout.profile)
        try write(catalogue.equipment, to: StoreLayout.equipment)
        try write(catalogue.exercises, to: StoreLayout.exercises)
        try write(catalogue.zoneSets, to: StoreLayout.zones)
        try write(catalogue.targets, to: StoreLayout.targets)
        try write(catalogue.foods, to: StoreLayout.foods)
        try write(catalogue.settings, to: StoreLayout.settings)
        let snapshot = currentSnapshot()
        lock.withLock {
            catalogueSnapshot = snapshot
            lastCatalogue = catalogue
        }
    }

    /// Nil when no catalogue file changed since the last load/save (or nothing was loaded yet, in which case
    /// this performs the first load). Otherwise reloads and returns what changed.
    public func reloadCatalogueIfChanged() throws -> CatalogueDiff? {
        let (previous, old) = lock.withLock { (catalogueSnapshot, lastCatalogue) }
        guard let previous, let old else {
            _ = try loadCatalogue()
            return nil
        }
        if currentSnapshot() == previous { return nil }
        let new = try loadCatalogue()
        return CatalogueDiff(old: old, new: new)
    }

    private func readCatalogue() throws -> (Catalogue, [String: Data]) {
        var snapshot: [String: Data] = [:]
        func read<T: Decodable>(_ path: String, _ fallback: T) throws -> T {
            guard let data = fm.contents(atPath: url(path).path) else { return fallback }
            snapshot[path] = data
            if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return fallback }
            do {
                return try JSONCoding.decode(T.self, from: data)
            } catch {
                throw FileStoreError.decode(path: path, underlying: String(describing: error))
            }
        }
        let c = Catalogue(
            profile: try read(StoreLayout.profile, Profile()),
            equipment: try read(StoreLayout.equipment, []),
            exercises: try read(StoreLayout.exercises, []),
            zoneSets: try read(StoreLayout.zones, []),
            targets: try read(StoreLayout.targets, []),
            foods: try read(StoreLayout.foods, []),
            settings: try read(StoreLayout.settings, Settings())
        )
        return (c, snapshot)
    }

    private func currentSnapshot() -> [String: Data] {
        var snapshot: [String: Data] = [:]
        for path in StoreLayout.catalogueFiles {
            if let data = fm.contents(atPath: url(path).path) { snapshot[path] = data }
        }
        return snapshot
    }

    // MARK: Sessions

    /// Writes `sessions/YYYY/<stem>.json` and, when a renderer is set, the `.md` sibling.
    public func saveSession(_ session: Session) throws {
        let path = StoreLayout.sessionPath(session, timeZone: timeZone)
        try write(session, to: path)
        if let render = markdownRenderer {
            let catalogue = try lock.withLock { lastCatalogue } ?? readCatalogue().0
            let mdPath = String(path.dropLast(".json".count)) + ".md"
            try writeText(render(session, catalogue), to: mdPath)
        }
    }

    /// All sessions (or those filed under `year`), sorted by start.
    public func loadSessions(year: Int? = nil) throws -> [Session] {
        let base = url(StoreLayout.sessionsDir)
        let years: [URL]
        if let year {
            years = [base.appendingPathComponent(String(year))]
        } else {
            years = ((try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? [])
        }
        var sessions: [Session] = []
        for dir in years {
            let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "json" {
                let data = try Data(contentsOf: file)
                do {
                    sessions.append(try JSONCoding.decode(Session.self, from: data))
                } catch {
                    throw FileStoreError.decode(path: file.path, underlying: String(describing: error))
                }
            }
        }
        return sessions.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    public func deleteSession(_ session: Session) throws {
        let path = StoreLayout.sessionPath(session, timeZone: timeZone)
        for p in [path, String(path.dropLast(".json".count)) + ".md"] where fm.fileExists(atPath: url(p).path) {
            try fm.removeItem(at: url(p))
        }
    }

    // MARK: Days and body

    public func saveDay(_ day: DaySnapshot) throws {
        try write(day, to: StoreLayout.dayPath(day.date))
    }

    public func loadDay(_ date: String) throws -> DaySnapshot? {
        guard let data = fm.contents(atPath: url(StoreLayout.dayPath(date)).path) else { return nil }
        return try JSONCoding.decode(DaySnapshot.self, from: data)
    }

    public func loadBodyMeasures() throws -> [BodyMeasure] {
        guard let data = fm.contents(atPath: url(StoreLayout.bodyMeasures).path) else { return [] }
        return try JSONCoding.decode([BodyMeasure].self, from: data)
    }

    public func saveBodyMeasures(_ measures: [BodyMeasure]) throws {
        try write(measures, to: StoreLayout.bodyMeasures)
    }

    // MARK: Advice

    /// `advice/*.md`, newest first. Title = first `# ` heading, else the stem. Date = `YYYY-MM-DD` stem prefix,
    /// else the file's modification date. Status from `advice/status.json`, default open.
    public func loadAdvice() throws -> [AdviceNote] {
        let dir = url(StoreLayout.adviceDir)
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let statuses = loadAdviceStatuses()
        let dayFormat = DateFormatter()
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        dayFormat.timeZone = timeZone
        dayFormat.dateFormat = "yyyy-MM-dd"
        var notes: [AdviceNote] = []
        for file in files where file.pathExtension == "md" {
            let stem = file.deletingPathExtension().lastPathComponent
            let body = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            let title = body.split(separator: "\n").first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            let date = dayFormat.date(from: String(stem.prefix(10)))
                ?? (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? Date(timeIntervalSince1970: 0)
            notes.append(AdviceNote(id: stem, title: title ?? stem, body: body, date: date, status: statuses[stem] ?? .open))
        }
        return notes.sorted { ($0.date, $0.id) > ($1.date, $1.id) }
    }

    /// Records status in `advice/status.json`; never touches the note itself.
    public func setAdviceStatus(id: String, status: AdviceStatus) throws {
        var statuses = loadAdviceStatuses()
        statuses[id] = status
        try write(statuses.mapValues(\.rawValue), to: StoreLayout.adviceStatus)
    }

    private func loadAdviceStatuses() -> [String: AdviceStatus] {
        guard let data = fm.contents(atPath: url(StoreLayout.adviceStatus).path),
              let raw = try? JSONCoding.decode([String: String].self, from: data) else { return [:] }
        return raw.compactMapValues(AdviceStatus.init(rawValue:))
    }

    // MARK: Derived

    /// Writes whatever `derivedRenderer` returns (README.md, schema.md, digest.md, log.csv). No-op without one.
    public func writeDerived(catalogue: Catalogue, sessions: [Session]) throws {
        guard let render = derivedRenderer else { return }
        for (path, text) in render(catalogue, sessions).sorted(by: { $0.key < $1.key }) {
            try writeText(text, to: path)
        }
    }

    // MARK: Low level

    public func write<T: Encodable>(_ value: T, to relative: String) throws {
        var data = try JSONCoding.encode(value)
        data.append(0x0A)
        try writeData(data, to: relative)
    }

    public func writeText(_ text: String, to relative: String) throws {
        try writeData(Data(text.utf8), to: relative)
    }

    private func writeData(_ data: Data, to relative: String) throws {
        let target = url(relative)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }
}

public enum FileStoreError: Error, Equatable, CustomStringConvertible {
    case decode(path: String, underlying: String)

    public var description: String {
        switch self {
        case let .decode(path, underlying): return "Could not read \(path): \(underlying)"
        }
    }
}
