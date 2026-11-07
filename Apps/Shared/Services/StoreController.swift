import Foundation
import Observation
import HealthAndICore

/// Owns the on-disk folder (the store and the Claude-readable export) and the in-memory catalogue.
@Observable @MainActor
final class StoreController {
    static let shared = StoreController()

    static let bookmarkKey = "export_folder_bookmark"
    static let iCloudContainer = "iCloud.com.andeye.health"

    var catalogue: Catalogue = .empty
    var sessions: [Session] = []
    var advice: [AdviceNote] = []
    var rootURL: URL = URL.documentsDirectory
    /// True when the folder had no catalogue: the UI asks whether to seed it from the starter pack.
    var needsStarterPackChoice = false
    /// Catalogue file edits detected on foreground, awaiting the user's confirmation.
    var pendingDiff: CatalogueDiff?
    var isUsingICloud = false
    var isUsingCustomFolder = false
    var lastError: String?

    private(set) var store: FileStore?
    private var scopedURL: URL?

    init() {}

    // MARK: Folder

    func bootstrap() {
        rootURL = resolveFolder()
        open(root: rootURL)
    }

    private func resolveFolder() -> URL {
        isUsingCustomFolder = false
        isUsingICloud = false
        #if os(iOS)
        if let url = resolveBookmark() {
            isUsingCustomFolder = true
            return url
        }
        if let container = FileManager.default.url(forUbiquityContainerIdentifier: Self.iCloudContainer) {
            isUsingICloud = true
            return container.appendingPathComponent("Documents", isDirectory: true)
        }
        #endif
        return URL.documentsDirectory
    }

    #if os(iOS)
    private func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
            return nil
        }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        stopScopedAccess()
        scopedURL = url
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        return url
    }

    /// Switch to a folder the user picked (document picker). Persists a security-scoped bookmark.
    func chooseFolder(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        do {
            let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        } catch {
            lastError = "Could not remember folder: \(error.localizedDescription)"
            if accessing { url.stopAccessingSecurityScopedResource() }
            return
        }
        stopScopedAccess()
        if accessing { scopedURL = url }
        isUsingCustomFolder = true
        isUsingICloud = false
        rootURL = url
        open(root: url)
    }
    #endif

    /// Forget a user-picked folder and return to the default (iCloud Drive, else local Documents).
    func resetFolder() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        stopScopedAccess()
        bootstrap()
    }

    private func stopScopedAccess() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    private func open(root: URL) {
        lastError = nil
        pendingDiff = nil
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } catch {
            lastError = "Could not create folder: \(error.localizedDescription)"
        }
        let store = FileStore(root: root, markdownRenderer: { SessionMarkdown.render($0, catalogue: $1) })
        self.store = store
        let catalogueDir = root.appendingPathComponent(StoreLayout.catalogueDir, isDirectory: true)
        if !FileManager.default.fileExists(atPath: catalogueDir.path) {
            catalogue = .empty
            sessions = []
            advice = []
            needsStarterPackChoice = true
            return
        }
        needsStarterPackChoice = false
        reloadAll()
    }

    func reloadAll() {
        guard let store else { return }
        do { catalogue = try store.loadCatalogue() } catch { report("load catalogue", error) }
        do { sessions = try store.loadSessions(year: nil).sorted { $0.start < $1.start } } catch { report("load sessions", error) }
        do { advice = try store.loadAdvice() } catch { report("load advice", error) }
    }

    /// Answer the empty-folder question: seed from the starter pack, or start with an empty catalogue.
    func chooseStarterPack(_ accept: Bool) {
        catalogue = accept ? StarterPack.load() : .empty
        needsStarterPackChoice = false
        save()
        writeDerived()
    }

    // MARK: Catalogue round-trip

    /// Call on foreground: detects hand edits (by Claude or Martin) to the catalogue files.
    func reloadCatalogueIfChanged() {
        guard let store, !needsStarterPackChoice else { return }
        do {
            if let diff = try store.reloadCatalogueIfChanged(), !diff.isEmpty {
                pendingDiff = diff
            }
        } catch {
            report("check catalogue", error)
        }
        do { advice = try store.loadAdvice() } catch { report("load advice", error) }
    }

    func acceptPendingDiff() {
        guard let store else { return }
        do { catalogue = try store.loadCatalogue() } catch { report("load catalogue", error) }
        pendingDiff = nil
    }

    /// Keep the in-app catalogue; the next save overwrites the edited files.
    func rejectPendingDiff() {
        pendingDiff = nil
        save()
    }

    func save() {
        guard let store else { return }
        do { try store.saveCatalogue(catalogue) } catch { report("save catalogue", error) }
    }

    /// Replace the whole catalogue (e.g. received from the phone on the watch) without re-asking.
    func applyCatalogue(_ new: Catalogue) {
        catalogue = new
        needsStarterPackChoice = false
        save()
    }

    // MARK: Sessions and advice

    func saveSession(_ session: Session) {
        guard let store else { return }
        do { try store.saveSession(session) } catch { report("save session", error); return }
        if let i = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[i] = session
        } else {
            sessions.append(session)
            sessions.sort { $0.start < $1.start }
        }
        writeDerived()
    }

    func setAdviceStatus(id: String, status: AdviceStatus) {
        guard let store else { return }
        do { try store.setAdviceStatus(id: id, status: status) } catch { report("save advice status", error); return }
        if let i = advice.firstIndex(where: { $0.id == id }) {
            advice[i].status = status
        }
    }

    /// Rewrites the Claude-facing summaries: README.md, schema.md, digest.md, log.csv.
    func writeDerived(now: Date = .now) {
        guard let store, isOn(.export) else { return }
        let days = recentDays(28, now: now)
        let files: [(String, String)] = [
            (StoreLayout.readme, ReadmeDoc.render()),
            (StoreLayout.schema, SchemaDoc.render()),
            (StoreLayout.digest, Digest.render(catalogue: catalogue, sessions: sessions, days: days, advice: advice, now: now)),
            (StoreLayout.logCSV, LogCSV.render(sessions: sessions, catalogue: catalogue)),
        ]
        for (path, text) in files {
            do { try store.writeText(text, to: path) } catch { report("write \(path)", error) }
        }
    }

    /// Saved day snapshots for the last `count` days, oldest first.
    func recentDays(_ count: Int, now: Date = .now) -> [DaySnapshot] {
        guard let store else { return [] }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        return (0..<count).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: now) else { return nil }
            return try? store.loadDay(f.string(from: d))
        }
    }

    func saveDay(_ day: DaySnapshot) {
        do { try store?.saveDay(day) } catch { report("save day", error) }
    }

    /// Readable Markdown for one session, for share sheets and previews.
    func markdown(for session: Session) -> String {
        SessionMarkdown.render(session, catalogue: catalogue)
    }

    // MARK: Modules

    func isOn(_ module: Module) -> Bool {
        catalogue.settings.isEnabled(module)
    }

    func set(_ module: Module, on: Bool) {
        catalogue.settings.setEnabled(module, on)
        save()
    }

    /// Closed-loop resistance is a post-v1 experiment, off unless the settings file switches it on.
    var closedLoopEnabled: Bool {
        catalogue.settings.isEnabled("closed_loop")
    }

    private func report(_ what: String, _ error: Error) {
        lastError = "Could not \(what): \(error.localizedDescription)"
    }
}
