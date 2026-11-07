import XCTest
@testable import HealthAndICore

final class ImportTests: XCTestCase {
    func testTrainingLogCSV() {
        var catalogue = Catalogue.empty
        catalogue.profile.timeZone = "UTC"
        catalogue.exercises = [Exercise(id: "ex-goblet-squat", name: "Goblet squat")]
        let csv = """
        Day , Movement,Side,Reps,Weight (kg),RIR,Notes\r
        04/09/2026,goblet  squat,,10,11.53,2,"slow, controlled"\r
        ,Single-arm row,L,12,11.53,1,\r
        ,Single-arm row,R,11,11.53,1,"said \"\"hard\"\""\r
        2026-09-06,Press-up,,15,,3,\r
        31/02/x,Press-up,,15,,3,\r
        2026-09-06,Press-up,,many,,3,\r
        2026-09-06,,,5,,,\r
        ,,,,,,\r

        """
        let result = TrainingLogCSVImporter().parse(csv: csv, catalogue: catalogue)
        XCTAssertEqual(result.sessions.map(\.id), ["2026-09-04-0000-weights", "2026-09-06-0000-weights"])
        XCTAssertEqual(result.sessions[0].start, ISO8601DateFormatter().date(from: "2026-09-04T00:00:00Z"))
        XCTAssertEqual(result.newExercises.map(\.id), ["ex-single-arm-row", "ex-press-up"])
        XCTAssertEqual(result.newExercises[0].name, "Single-arm row")
        XCTAssertTrue(result.newExercises[0].unilateral)
        XCTAssertFalse(result.newExercises[1].unilateral)

        let sets = result.sessions[0].sets
        XCTAssertEqual(sets.count, 3)
        XCTAssertEqual(sets[0].exerciseId, "ex-goblet-squat")
        XCTAssertEqual(sets[0].reps, 10)
        XCTAssertEqual(sets[0].load, Load(fixedKg: 11.53))
        XCTAssertEqual(sets[0].rir, 2)
        XCTAssertEqual(sets[0].notes, "slow, controlled")
        XCTAssertEqual(sets[1].side, .left)
        XCTAssertEqual(sets[2].side, .right)
        XCTAssertEqual(sets[2].notes, "said \"hard\"")
        XCTAssertEqual(Set(sets.map(\.id)).count, 3)

        XCTAssertEqual(result.sessions[1].sets.count, 1)
        XCTAssertNil(result.sessions[1].sets[0].load)
        XCTAssertEqual(result.warnings.count, 3, "\(result.warnings)")
        XCTAssertTrue(result.warnings.contains { $0.contains("Row 6") && $0.contains("date") })
        XCTAssertTrue(result.warnings.contains { $0.contains("Row 7") && $0.contains("reps") })
        XCTAssertTrue(result.warnings.contains { $0.contains("Row 8") && $0.contains("exercise") })
    }

    func testMissingColumnsWarns() {
        let result = TrainingLogCSVImporter().parse(csv: "foo,bar\n1,2\n", catalogue: .empty)
        XCTAssertTrue(result.sessions.isEmpty)
        XCTAssertEqual(result.warnings.count, 2)
    }

    func testCustomColumnMapAndDates() {
        let importer = TrainingLogCSVImporter(columnMap: ["date": "when", "exercise": "what", "reps": "n"])
        let result = importer.parse(csv: "When,What,N\n2026-09-04T08:00,Curl,8\n", catalogue: .empty)
        XCTAssertEqual(result.sessions.first?.sets.first?.reps, 8)
        XCTAssertEqual(TrainingLogCSVImporter.parseDate("4/9/26"), "2026-09-04")
        XCTAssertNil(TrainingLogCSVImporter.parseDate("13/13/2026"))
    }
}
