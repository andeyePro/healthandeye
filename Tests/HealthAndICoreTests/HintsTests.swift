import XCTest
@testable import HealthAndICore

final class HintsTests: XCTestCase {
    let day0 = ISO8601DateFormatter().date(from: "2026-11-01T08:00:00Z")!

    func catalogue(_ rules: ProgressionRules = ProgressionRules()) -> Catalogue {
        var c = Catalogue.empty
        c.profile.timeZone = "UTC"
        c.exercises = [Exercise(id: "ex-curl", name: "Curl", targetRepMin: 8, targetRepMax: 12)]
        c.settings.progression = rules
        return c
    }

    func session(_ id: String, _ start: Date, _ sets: [(Int, Double, Double)], side: Side = .both) -> Session {
        Session(id: id, start: start, type: "weights", sets: sets.enumerated().map { i, s in
            SetEntry(id: "\(id)-\(i)", exerciseId: "ex-curl", side: side, reps: s.0, load: Load(fixedKg: s.1), rir: s.2)
        })
    }

    func kinds(_ hints: [Hint]) -> [String] { hints.map(\.kind) }

    func testTooLight() {
        let s = session("a", day0, [(15, 10, 3)])
        XCTAssertEqual(kinds(ProgressionAdvisor.hints(for: s, history: [], catalogue: catalogue())), ["too_light"])
        XCTAssertEqual(kinds(ProgressionAdvisor.hints(for: session("b", day0, [(14, 10, 3)]), history: [], catalogue: catalogue())), [])
        XCTAssertEqual(kinds(ProgressionAdvisor.hints(for: session("c", day0, [(15, 10, 2)]), history: [], catalogue: catalogue())), [])
        let looser = ProgressionRules(tooLightRepsAbove: 2, tooLightRirAtLeast: 2)
        XCTAssertEqual(kinds(ProgressionAdvisor.hints(for: session("d", day0, [(14, 10, 2)]), history: [], catalogue: catalogue(looser))), ["too_light"])
    }

    func testUnderWarmed() {
        XCTAssertEqual(kinds(ProgressionAdvisor.hints(for: session("a", day0, [(8, 10, 1), (10, 10, 1)]), history: [], catalogue: catalogue())), ["under_warmed"])
        XCTAssertEqual(kinds(ProgressionAdvisor.hints(for: session("b", day0, [(8, 10, 1), (9, 10, 1)]), history: [], catalogue: catalogue())), [])
        XCTAssertEqual(kinds(ProgressionAdvisor.hints(for: session("c", day0, [(8, 12, 1), (10, 10, 1)]), history: [], catalogue: catalogue())), [])
        var mixed = session("d", day0, [(8, 10, 1)], side: .left)
        mixed.sets.append(SetEntry(id: "d-r", exerciseId: "ex-curl", side: .right, reps: 10, load: Load(fixedKg: 10), rir: 1))
        XCTAssertEqual(kinds(ProgressionAdvisor.hints(for: mixed, history: [], catalogue: catalogue())), [])
        XCTAssertEqual(kinds(ProgressionAdvisor.hints(for: session("e", day0, [(8, 10, 1), (9, 10, 1)]), history: [],
                                                      catalogue: catalogue(ProgressionRules(underWarmedRepRise: 1)))), ["under_warmed"])
    }

    func testLoadDropped() {
        let earlier = session("old", day0, [(10, 12, 1)])
        let newer = session("mid", day0 + 86_400, [(10, 11, 1)])
        let now = session("now", day0 + 2 * 86_400, [(10, 10, 1)])
        let hints = ProgressionAdvisor.hints(for: now, history: [earlier, newer, now], catalogue: catalogue())
        XCTAssertEqual(kinds(hints), ["load_dropped"])
        XCTAssertTrue(hints[0].message.contains("down from 11 kg on 2026-11-02"))
        XCTAssertEqual(kinds(ProgressionAdvisor.hints(for: session("x", day0 + 3 * 86_400, [(10, 11, 1)]), history: [newer], catalogue: catalogue())), [])
    }

    func testDisabled() {
        let s = session("a", day0, [(15, 10, 3), (18, 10, 3)])
        XCTAssertEqual(ProgressionAdvisor.hints(for: s, history: [], catalogue: catalogue(ProgressionRules(enabled: false))), [])
    }
}
