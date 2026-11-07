import XCTest
@testable import HealthAndICore

final class LoadBuilderTests: XCTestCase {
    let catalogue = StarterPack.catalogue

    func testStarterDumbbellIs11_53PerHand() throws {
        let total = try XCTUnwrap(LoadBuilder.totalKg(StarterPack.dumbbellLoad, catalogue: catalogue))
        XCTAssertEqual(total, 1.47 + 5.03 + 4.92 + 2 * 0.0531, accuracy: 1e-9)
        XCTAssertEqual(total, 11.53, accuracy: 0.005)
    }

    func testBreakdown() {
        let load = Load(parts: StarterPack.dumbbellLoad.parts, fixedKg: 1)
        let rows = LoadBuilder.breakdown(load, catalogue: catalogue)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows[3].count, 2)
        XCTAssertEqual(rows[3].kg, 0.1062, accuracy: 1e-9)
        XCTAssertEqual(rows.last?.name, "fixed")
    }

    func testTotalNilWhenUnknown() {
        XCTAssertNil(LoadBuilder.totalKg(Load(), catalogue: catalogue))
        XCTAssertNil(LoadBuilder.totalKg(Load(parts: [LoadPart(equipmentId: "eq-nope")]), catalogue: catalogue))
        XCTAssertEqual(LoadBuilder.totalKg(Load(fixedKg: 5), catalogue: catalogue), 5)
    }

    func testNoWarningsForStarterLoad() {
        let ex = catalogue.exercise(id: "ex-single-arm-row")
        XCTAssertEqual(LoadBuilder.limitWarnings(load: StarterPack.dumbbellLoad, exercise: ex, catalogue: catalogue), [])
    }

    func testBenchDumbbellLimitExceeded() {
        let ex = catalogue.exercise(id: "ex-single-arm-row")
        let warnings = LoadBuilder.limitWarnings(load: Load(fixedKg: 26), exercise: ex, catalogue: catalogue)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("dumbbell"))
    }

    func testPerSleeveExceeded() {
        let load = Load(parts: [
            LoadPart(equipmentId: "eq-dumbbell-bar", count: 1),
            LoadPart(equipmentId: "eq-plate-5-03", count: 2),
            LoadPart(equipmentId: "eq-plate-4-92", count: 1),
        ])
        let warnings = LoadBuilder.limitWarnings(load: load, exercise: nil, catalogue: catalogue)
        XCTAssertFalse(warnings.isEmpty)
        XCTAssertTrue(warnings.allSatisfy { $0.contains("per sleeve") })
    }
}
