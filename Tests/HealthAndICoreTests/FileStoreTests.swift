import XCTest
@testable import HealthAndICore

final class FileStoreTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("healthandi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func exists(_ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(rel).path)
    }

    func testCatalogueRoundTrip() throws {
        let store = FileStore(root: root)
        XCTAssertEqual(try store.loadCatalogue(), .empty)
        try store.saveCatalogue(StarterPack.catalogue)
        for f in StoreLayout.catalogueFiles { XCTAssertTrue(exists(f), f) }
        XCTAssertEqual(try FileStore(root: root).loadCatalogue(), StarterPack.catalogue)
    }

    func testSessionSaveLoadAndMarkdownSibling() throws {
        let utc = TimeZone(identifier: "UTC")!
        let store = FileStore(root: root, timeZone: utc, markdownRenderer: { s, c in "# \(s.type) \(c.exercises.count)" })
        try store.saveCatalogue(StarterPack.catalogue)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        let start = cal.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 7, minute: 5))!
        let session = Session(id: "s1", start: start, type: "weights",
                              sets: [SetEntry(id: "s1-1", exerciseId: "ex-goblet-squat", reps: 10, load: StarterPack.dumbbellLoad, rir: 2)],
                              summary: ["avg_hr": 100])
        try store.saveSession(session)
        XCTAssertTrue(exists("sessions/2026/2026-11-07-0705-weights.json"))
        let md = try String(contentsOf: root.appendingPathComponent("sessions/2026/2026-11-07-0705-weights.md"), encoding: .utf8)
        XCTAssertEqual(md, "# weights 9")

        let older = Session(id: "s0", start: start.addingTimeInterval(-86400 * 400), type: "rowing")
        try store.saveSession(older)
        XCTAssertEqual(try store.loadSessions(year: nil).map(\.id), ["s0", "s1"])
        XCTAssertEqual(try store.loadSessions(year: 2026), [session])
        XCTAssertEqual(try store.loadSessions(year: 2030), [])
    }

    func testReloadCatalogueIfChangedReturnsDiff() throws {
        let store = FileStore(root: root)
        try store.saveCatalogue(StarterPack.catalogue)
        _ = try store.loadCatalogue()
        XCTAssertNil(try store.reloadCatalogueIfChanged())

        var equipment = StarterPack.catalogue.equipment
        equipment[0].limits["dumbbell_max_kg"] = 30
        equipment.removeLast()
        equipment.append(Equipment(id: "eq-kettlebell", name: "Kettlebell", kind: "dumbbell", massKg: 12))
        let data = try JSONCoding.encode(equipment)
        try data.write(to: root.appendingPathComponent(StoreLayout.equipment))

        let diff = try XCTUnwrap(try store.reloadCatalogueIfChanged())
        XCTAssertFalse(diff.isEmpty)
        XCTAssertTrue(diff.lines.contains("~ equipment eq-woodrower: limits"), "\(diff.lines)")
        XCTAssertTrue(diff.lines.contains("+ equipment eq-kettlebell (Kettlebell)"), "\(diff.lines)")
        XCTAssertTrue(diff.lines.contains { $0.hasPrefix("- equipment eq-band-purple") }, "\(diff.lines)")
        XCTAssertNil(try store.reloadCatalogueIfChanged())
    }

    func testAdviceStatusAndDays() throws {
        let store = FileStore(root: root, timeZone: TimeZone(identifier: "UTC")!)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("advice"), withIntermediateDirectories: true)
        let text = "# Add a set\n\nTry a third set of rows.\n"
        try text.write(to: root.appendingPathComponent("advice/2026-11-07-rows.md"), atomically: true, encoding: .utf8)
        var notes = try store.loadAdvice()
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].id, "2026-11-07-rows")
        XCTAssertEqual(notes[0].title, "Add a set")
        XCTAssertEqual(notes[0].status, .open)
        try store.setAdviceStatus(id: "2026-11-07-rows", status: .done)
        notes = try store.loadAdvice()
        XCTAssertEqual(notes[0].status, .done)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("advice/2026-11-07-rows.md"), encoding: .utf8), text)

        let day = DaySnapshot(date: "2026-11-07", totals: ["protein_g": 120])
        try store.saveDay(day)
        XCTAssertTrue(exists("daily/2026/2026-11-07.json"))
        XCTAssertEqual(try store.loadDay("2026-11-07"), day)
    }

    func testWriteDerived() throws {
        let store = FileStore(root: root, derivedRenderer: { c, s in
            [StoreLayout.readme: "readme", StoreLayout.logCSV: "n,\(s.count),\(c.equipment.count)"]
        })
        try store.writeDerived(catalogue: .empty, sessions: [])
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("log.csv"), encoding: .utf8), "n,0,0")
        XCTAssertTrue(exists("README.md"))
    }
}
