import XCTest
@testable import HealthAndICore

final class RowingSessionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let zones = ZoneSet(id: "zs-hr", name: "HR", metric: .heartRate, zones: [
        Zone(name: "z2", lower: 120, upper: 140),
        Zone(name: "z3", lower: 141, upper: 160),
    ])

    func testZoneStatesAndCueMapping() {
        let e = ZoneEngine(zoneSet: zones, zoneName: "z2")
        XCTAssertEqual(e.state(for: 119), .below)
        XCTAssertEqual(e.state(for: 130), .inBand)
        XCTAssertEqual(e.state(for: 141), .above)
        XCTAssertEqual(e.cue(previous: .inBand, current: .below), .goHarder)
        XCTAssertEqual(e.cue(previous: .inBand, current: .above), .easeOff)
        XCTAssertEqual(e.cue(previous: .above, current: .inBand), .backInBand)
        XCTAssertNil(e.cue(previous: .inBand, current: .inBand))
        XCTAssertNil(e.cue(previous: nil, current: .below))
    }

    func testZoneCueHysteresisAndThrottle() {
        var e = ZoneEngine(zoneSet: zones, zoneName: "z2")
        XCTAssertNil(e.update(hr: 130, at: t0))
        XCTAssertNil(e.update(hr: 119, at: t0 + 5), "inside hysteresis margin")
        XCTAssertEqual(e.update(hr: 117, at: t0 + 6), .goHarder)
        XCTAssertNil(e.update(hr: 125, at: t0 + 8), "throttled by min seconds")
        XCTAssertEqual(e.update(hr: 125, at: t0 + 16), .backInBand)
        XCTAssertNil(e.update(hr: 141, at: t0 + 30), "inside hysteresis margin")
        XCTAssertEqual(e.update(hr: 143, at: t0 + 31), .easeOff)
        XCTAssertNil(e.update(hr: 143, at: t0 + 60), "no repeat cue for an unchanged state")
    }

    func testZoneCueConfigurable() {
        var e = ZoneEngine(zoneSet: zones, zoneName: "z2", hysteresisBpm: 0, minSecondsBetweenCues: 0)
        XCTAssertNil(e.update(hr: 130, at: t0))
        XCTAssertEqual(e.update(hr: 119, at: t0 + 1), .goHarder)
        XCTAssertEqual(e.update(hr: 120, at: t0 + 1), .backInBand)
    }

    private func flatHR(_ bpm: Double, minutes: Int) -> IntervalSeries {
        IntervalSeries(metric: "heart_rate", unit: "bpm", source: .polarH10,
                       samples: (0...(minutes * 60)).map { Sample(t: Double($0), v: bpm) })
    }

    private func dob(ageYears: Double, at date: Date) -> Date {
        date.addingTimeInterval(-ageYears * 365.2425 * 86_400)
    }

    func testEnergyFlat120For10Minutes() throws {
        let male = Profile(dateOfBirth: dob(ageYears: 40, at: t0), sex: .male, bodyMassKg: 80)
        let kcal = try XCTUnwrap(EnergyEstimator.kcal(hrSeries: flatHR(120, minutes: 10), profile: male, on: t0))
        XCTAssertEqual(kcal, 10 * (-55.0969 + 0.6309 * 120 + 0.1988 * 80 + 0.2017 * 40) / 4.184, accuracy: 1e-6)
        XCTAssertEqual(kcal, 106.56, accuracy: 0.01)

        let female = Profile(dateOfBirth: dob(ageYears: 40, at: t0), sex: .female, bodyMassKg: 80)
        let fk = try XCTUnwrap(EnergyEstimator.kcal(hrSeries: flatHR(120, minutes: 10), profile: female, on: t0))
        XCTAssertEqual(fk, 10 * (-20.4022 + 0.4472 * 120 - 0.1263 * 80 + 0.074 * 40) / 4.184, accuracy: 1e-6)
    }

    func testEnergyNilWhenProfileIncomplete() {
        let series = flatHR(120, minutes: 1)
        XCTAssertNil(EnergyEstimator.kcal(hrSeries: series, profile: Profile(sex: .male, bodyMassKg: 80), on: t0))
        XCTAssertNil(EnergyEstimator.kcal(hrSeries: series, profile: Profile(dateOfBirth: dob(ageYears: 40, at: t0), bodyMassKg: 80), on: t0))
        XCTAssertNil(EnergyEstimator.kcal(hrSeries: series, profile: Profile(dateOfBirth: dob(ageYears: 40, at: t0), sex: .male), on: t0))
    }

    func testRecorderSeriesAndSummary() throws {
        var rec = SessionRecorder(start: t0)
        for s in 0...600 {
            let at = t0 + Double(s)
            rec.add(metric: "heart_rate", unit: "bpm", source: .polarH10, value: s < 300 ? 110 : 130, at: at)
            if s % 60 == 0 {
                rec.add(metric: "heart_rate", unit: "bpm", source: .machine, value: 90, at: at)
                rec.add(metric: "distance_m", unit: "m", source: .machine, value: Double(s) * 4, at: at)
                rec.add(metric: "stroke_rate", unit: "spm", source: .machine, value: s < 300 ? 20 : 24, at: at)
                rec.add(metric: "pace_s_per_500m", unit: "s/500m", source: .machine, value: 125, at: at)
                rec.add(metric: "energy_kcal", unit: "kcal", source: .machine, value: Double(s) / 6, at: at)
            }
        }
        let series = rec.series()
        XCTAssertEqual(series.map(\.metric), ["heart_rate", "heart_rate", "distance_m", "stroke_rate", "pace_s_per_500m", "energy_kcal"])
        XCTAssertEqual(series[0].source, .polarH10)
        XCTAssertEqual(series[0].samples.count, 601)
        XCTAssertEqual(series[1].source, .machine)
        XCTAssertEqual(series[1].samples.count, 11)

        let sum = rec.summary(zoneSet: zones, zoneName: "z2")
        XCTAssertEqual(sum["distance_m"], 2400)
        XCTAssertEqual(sum["max_hr"], 130)
        XCTAssertEqual(try XCTUnwrap(sum["avg_hr"]), (300 * 110 + 301 * 130) / 601.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(sum["minutes_in_zone"]), 5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(sum["avg_stroke_rate"]), (5 * 20 + 6 * 24) / 11.0, accuracy: 1e-9)
        XCTAssertEqual(sum["avg_pace"], 125)
        XCTAssertEqual(sum["energy_kcal_console"], 100)

        XCTAssertNil(rec.summary(zoneSet: nil, zoneName: nil)["minutes_in_zone"])
        XCTAssertTrue(SessionRecorder(start: t0).summary(zoneSet: zones, zoneName: "z2").isEmpty)
    }

    func testResistanceControllerPI() {
        var c = ResistanceController(targetHR: 130, kp: 0.1, ki: 0.01, min: 1, max: 10, initial: 5)
        XCTAssertEqual(c.step(hr: 150, dt: 1), 5 - 2 - 0.2, accuracy: 1e-9)
        XCTAssertEqual(c.step(hr: 130, dt: 1), 5 - 0.2, accuracy: 1e-9, "integral holds the past error")
        XCTAssertEqual(c.step(hr: 200, dt: 1), 1, "clamped to min")
        let integralWhileSaturated = c.integral
        _ = c.step(hr: 200, dt: 10)
        XCTAssertEqual(c.integral, integralWhileSaturated, "no wind-up while saturated")
        XCTAssertGreaterThan(c.step(hr: 100, dt: 1), 5, "HR below target raises resistance")
        XCTAssertEqual(c.step(hr: 0, dt: 1000), 10, "clamped to max")
    }
}
