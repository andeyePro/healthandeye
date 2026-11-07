import XCTest
@testable import HealthAndICore

final class ModelTests: XCTestCase {
    private func roundTrip<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try JSONCoding.encode(value)
        let back = try JSONCoding.decode(T.self, from: data)
        XCTAssertEqual(back, value, file: file, line: line)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONCoding.decode(type, from: Data(json.utf8))
    }

    let date = Date(timeIntervalSince1970: 1_794_000_000)

    func testRoundTripFullyPopulated() throws {
        let load = Load(parts: [LoadPart(equipmentId: "eq-bar", count: 1)], fixedKg: 2, perHand: false, label: "x")
        try roundTrip(Profile(heightCm: 180, dateOfBirth: date, sex: .male, maxHR: 180, maxHRFormula: .tanaka,
                              restingHR: 55, units: .metric, timeZone: "Europe/London", bodyMassKg: 80))
        try roundTrip(Equipment(id: "eq-a", name: "A", kind: "rower", massKg: 1, quantity: 2,
                                limits: ["dumbbell_max_kg": 25], connection: Connection(bleName: "R", protocolName: "ftms", hrRelay: true),
                                quirks: ["q"], notes: "n", enabled: false))
        try roundTrip(load)
        try roundTrip(Exercise(id: "ex-a", name: "A", pattern: "pull", unilateral: true, measure: .time,
                               equipmentIds: ["eq-a"], defaultRestSeconds: 90, targetRepMin: 8, targetRepMax: 12,
                               notes: "n", enabled: false))
        try roundTrip(ZoneSet(id: "zs", name: "Z", metric: .power, zones: [Zone(name: "Z2", lower: 1, upper: 2)]))
        try roundTrip(Target(id: "t", metric: "minutes_in_zone", period: .week, value: 175, zoneSetId: "zs", zoneName: "Z2", enabled: false))
        let set = SetEntry(id: "s1", exerciseId: "ex-a", side: .left, reps: 10, seconds: 30, meters: 5, load: load, rir: 2,
                           rpe: 8, restBeforeSeconds: 90, restInterrupted: true, variantTags: ["v"], notes: "n", timestamp: date)
        try roundTrip(set)
        try roundTrip(Session(id: "sess", start: date, end: date.addingTimeInterval(60), type: "rowing", notes: "n",
                              healthKitWorkoutId: "hk", hrSource: .polarH10, equipmentIds: ["eq-a"], sets: [set],
                              intervals: [IntervalSeries(metric: "heart_rate", unit: "bpm", source: .polarH10,
                                                         samples: [Sample(t: 1, v: 100)])],
                              summary: ["distance_m": 1000, "avg_hr": 115]))
        try roundTrip(Food(id: "f", name: "F", per100g: ["protein_g": 10], servings: [Serving(name: "s", grams: 30)]))
        try roundTrip(Intake(id: "i", foodId: "f", grams: 50, time: date))
        try roundTrip(BodyMeasure(id: "b", metric: "weight_kg", value: 80, time: date, source: .healthKit))
        try roundTrip(AdviceNote(id: "a", title: "T", body: "B", date: date, status: .done))
        try roundTrip(Settings(modules: ["rowing": true, "health_kit_read": false], effortScale: .rpe, setNotation: "reps@RPE",
                               hudTiles: ["zone"], progression: ProgressionRules(enabled: false, tooLightRepsAbove: 4,
                                                                                 tooLightRirAtLeast: 2, underWarmedRepRise: 3),
                               zoneCues: false, energyPrefersHR: false))
        try roundTrip(DaySnapshot(date: "2026-11-07", metrics: ["steps": 1000], intake: [Intake(id: "i", foodId: "f", grams: 1, time: date)],
                                  totals: ["energy_kcal": 100], targets: [TargetProgress(targetId: "t", value: 1, target: 2, met: false)]))
        try roundTrip(StarterPack.catalogue)
    }

    func testAbsentOptionalsDecodeToDefaults() throws {
        XCTAssertEqual(try decode(Profile.self, "{}"), Profile())
        let eq = try decode(Equipment.self, #"{"id":"eq-a","name":"A","unknown_key":1}"#)
        XCTAssertEqual(eq, Equipment(id: "eq-a", name: "A"))
        XCTAssertTrue(eq.enabled)
        XCTAssertEqual(try decode(Connection.self, "{}"), Connection())
        XCTAssertEqual(try decode(Load.self, "{}"), Load())
        XCTAssertEqual(try decode(LoadPart.self, #"{"equipment_id":"x"}"#), LoadPart(equipmentId: "x", count: 1))
        XCTAssertEqual(try decode(Exercise.self, #"{"id":"e","name":"E"}"#), Exercise(id: "e", name: "E"))
        XCTAssertEqual(try decode(ZoneSet.self, #"{"id":"z","name":"Z"}"#), ZoneSet(id: "z", name: "Z"))
        XCTAssertEqual(try decode(Zone.self, #"{"name":"Z"}"#), Zone(name: "Z"))
        XCTAssertEqual(try decode(Target.self, #"{"id":"t"}"#), Target(id: "t"))
        XCTAssertEqual(try decode(SetEntry.self, #"{"id":"s","exercise_id":"e"}"#), SetEntry(id: "s", exerciseId: "e"))
        XCTAssertEqual(try decode(Sample.self, "{}"), Sample(t: 0, v: 0))
        XCTAssertEqual(try decode(IntervalSeries.self, #"{"metric":"heart_rate"}"#), IntervalSeries(metric: "heart_rate"))
        let s = try decode(Session.self, #"{"id":"s","start":"2026-11-07T10:00:00Z"}"#)
        XCTAssertEqual(s.type, "other")
        XCTAssertNil(s.end)
        XCTAssertTrue(s.sets.isEmpty && s.intervals.isEmpty && s.summary.isEmpty)
        XCTAssertEqual(try decode(Food.self, #"{"id":"f","name":"F"}"#), Food(id: "f", name: "F"))
        XCTAssertEqual(try decode(Serving.self, #"{"name":"s"}"#), Serving(name: "s"))
        XCTAssertEqual(try decode(Intake.self, #"{"id":"i","food_id":"f","time":"2026-11-07T10:00:00Z"}"#).grams, 0)
        XCTAssertEqual(try decode(BodyMeasure.self, #"{"id":"b","metric":"weight_kg","time":"2026-11-07T10:00:00Z"}"#).source, .manual)
        let a = try decode(AdviceNote.self, #"{"id":"a","date":"2026-11-07T10:00:00Z"}"#)
        XCTAssertEqual(a.title, "a")
        XCTAssertEqual(a.status, .open)
        XCTAssertEqual(try decode(ProgressionRules.self, "{}"), ProgressionRules())
        XCTAssertEqual(try decode(Settings.self, "{}"), Settings())
        XCTAssertEqual(try decode(TargetProgress.self, "{}"), TargetProgress(targetId: ""))
        XCTAssertEqual(try decode(DaySnapshot.self, #"{"date":"2026-11-07"}"#), DaySnapshot(date: "2026-11-07"))
        XCTAssertEqual(try decode(Catalogue.self, "{}"), Catalogue.empty)
    }

    func testEncodingIsSnakeCaseAndOmitsNil() throws {
        let eq = Equipment(id: "eq-a", name: "A", massKg: 1.5, limits: ["dumbbell_max_kg": 25],
                           connection: Connection(protocolName: "ftms", hrRelay: true))
        let json = String(decoding: try JSONCoding.encode(eq), as: UTF8.self)
        XCTAssertTrue(json.contains("\"mass_kg\""))
        XCTAssertTrue(json.contains("\"dumbbell_max_kg\""))
        XCTAssertTrue(json.contains("\"protocol_name\""))
        XCTAssertTrue(json.contains("\"hr_relay\""))
        XCTAssertFalse(json.contains("\"notes\""))
        XCTAssertFalse(json.contains("\"quantity\""))
        let back = try JSONCoding.decode(Equipment.self, from: Data(json.utf8))
        XCTAssertEqual(back.limits["dumbbell_max_kg"], 25)

        let p = String(decoding: try JSONCoding.encode(Profile(maxHR: 173, restingHR: 50)), as: UTF8.self)
        XCTAssertTrue(p.contains("\"max_hr\""))
        XCTAssertTrue(p.contains("\"resting_hr\""))

        let s = String(decoding: try JSONCoding.encode(Settings(modules: ["health_kit_read": true])), as: UTF8.self)
        XCTAssertTrue(s.contains("\"health_kit_read\""))
        XCTAssertTrue(s.contains("\"energy_prefers_hr\""))
        XCTAssertTrue(s.contains("\"hud_tiles\""))

        let d = String(decoding: try JSONCoding.encode(Session(id: "s", start: Date(timeIntervalSince1970: 0))), as: UTF8.self)
        XCTAssertTrue(d.contains("1970-01-01T00:00:00Z"))
    }

    func testSettingsModuleDefaults() {
        var s = Settings()
        XCTAssertTrue(s.isEnabled(.weights))
        XCTAssertTrue(s.isEnabled(.export))
        XCTAssertTrue(s.isEnabled(.rowing))
        XCTAssertFalse(s.isEnabled(.nutrition))
        XCTAssertFalse(s.isEnabled(.healthKitWrite))
        s.setEnabled(.rowing, true)
        s.setEnabled(.weights, false)
        XCTAssertTrue(s.isEnabled(.rowing))
        XCTAssertFalse(s.isEnabled(.weights))
        XCTAssertEqual(s.hudTiles.first, "heart_rate")
        XCTAssertEqual(s.setNotation, "reps@RIR")
        XCTAssertEqual(s.effortScale, .rir)
    }

    func testZoneLookup() {
        let zs = ZoneSet(id: "z", name: "Z", zones: [Zone(name: "Zone 2", lower: 110, upper: 120)])
        XCTAssertEqual(zs.zone(for: 115)?.name, "Zone 2")
        XCTAssertEqual(zs.zone(for: 110)?.name, "Zone 2")
        XCTAssertNil(zs.zone(for: 121))
    }

    func testResolvedMaxHR() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let dob = cal.date(from: DateComponents(year: 1979, month: 1, day: 1))!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 7))!
        XCTAssertEqual(Profile(dateOfBirth: dob, maxHRFormula: .fox, timeZone: "UTC").resolvedMaxHR(on: now), 173)
        XCTAssertEqual(Profile(dateOfBirth: dob, maxHRFormula: .tanaka, timeZone: "UTC").resolvedMaxHR(on: now), 175)
        XCTAssertEqual(Profile(dateOfBirth: dob, maxHR: 181, maxHRFormula: .measured).resolvedMaxHR(on: now), 181)
        XCTAssertEqual(Profile(maxHR: 170, maxHRFormula: .fox).resolvedMaxHR(on: now), 170)
        XCTAssertNil(Profile().resolvedMaxHR(on: now))
    }

    func testStarterPackBundledMatchesCode() {
        let pack = StarterPack.load()
        XCTAssertEqual(pack, StarterPack.catalogue)
        XCTAssertEqual(pack.profile, Profile())
        XCTAssertTrue(pack.targets.isEmpty)
        XCTAssertEqual(pack.equipment(id: "eq-woodrower")?.quirks.count, 2)
        XCTAssertEqual(pack.equipment(id: "eq-polar-h10")?.notes, "max 2 Bluetooth connections")
        XCTAssertEqual(pack.exercises.count, 9)
        XCTAssertEqual(pack.zoneSets.first?.zones.first?.name, "Zone 2")
        #if SWIFT_PACKAGE
        XCTAssertNotNil(StarterPack.loadBundled(), "starter pack JSON should be bundled as a resource")
        #endif
    }
}
