import XCTest
@testable import HealthAndICore

final class ExportTests: XCTestCase {
    let start = ISO8601DateFormatter().date(from: "2026-11-05T07:30:00Z")!

    var catalogue: Catalogue {
        var c = Catalogue.empty
        c.profile.timeZone = "UTC"
        c.equipment = [
            Equipment(id: "eq-bar", name: "Dumbbell bar", kind: "bar", massKg: 1.47),
            Equipment(id: "eq-plate", name: "Plate 5.03", kind: "plate", massKg: 5.03),
            Equipment(id: "eq-rower", name: "WoodRower", kind: "rower"),
        ]
        c.exercises = [
            Exercise(id: "ex-goblet-squat", name: "Goblet squat", targetRepMin: 8, targetRepMax: 12),
            Exercise(id: "ex-row", name: "Single-arm row", unilateral: true),
        ]
        c.targets = [
            Target(id: "t-zone2", metric: "minutes_in_zone", period: .week, value: 175, zoneName: "Zone 2"),
            Target(id: "t-protein", metric: "protein_g", period: .day, value: 130),
        ]
        return c
    }

    var weights: Session {
        let load = Load(parts: [LoadPart(equipmentId: "eq-bar"), LoadPart(equipmentId: "eq-plate", count: 2)])
        return Session(id: "2026-11-05-0730-weights", start: start, end: start + 1800, type: "weights",
                       hrSource: .appleWatch, equipmentIds: ["eq-bar"], sets: [
                           SetEntry(id: "s1", exerciseId: "ex-goblet-squat", reps: 10, load: load, rir: 2,
                                    restBeforeSeconds: 90, variantTags: ["heels raised"], notes: "felt good, deep"),
                           SetEntry(id: "s2", exerciseId: "ex-row", side: .left, reps: 12, load: Load(fixedKg: 5), rir: 1),
                           SetEntry(id: "s3", exerciseId: "ex-goblet-squat", reps: 9, load: load, rir: 1, notes: "said \"ouch\""),
                       ])
    }

    var rowing: Session {
        let hr = IntervalSeries(metric: "heart_rate", unit: "bpm", source: .polarH10,
                                samples: (0..<180).map { Sample(t: Double($0), v: $0 < 60 ? 100 : 120) })
        return Session(id: "2026-11-06-0700-rowing", start: start + 86_400, end: start + 86_400 + 1200, type: "rowing",
                       hrSource: .polarH10, equipmentIds: ["eq-rower"], intervals: [hr],
                       summary: ["distance_m": 4000, "avg_hr": 115, "minutes_in_zone": 16, "energy_kcal_console": 200])
    }

    func testSessionMarkdownWeights() {
        let md = SessionMarkdown.render(weights, catalogue: catalogue)
        XCTAssertTrue(md.contains("# Weights session 2026-11-05 07:30"))
        XCTAssertTrue(md.contains("- Duration: 30:00 (30 min)"))
        XCTAssertTrue(md.contains("- HR source: apple_watch"))
        XCTAssertTrue(md.contains("- Equipment: Dumbbell bar (`eq-bar`)"))
        XCTAssertTrue(md.contains("### Goblet squat (`ex-goblet-squat`)"))
        XCTAssertTrue(md.contains("| 1 | both | 10 reps | 11.53 kg per hand (1× Dumbbell bar = 1.47 kg + 2× Plate 5.03 = 10.06 kg) | RIR 2 | 90 s | heels raised | felt good, deep |"))
        XCTAssertTrue(md.contains("| 2 | both | 9 reps |"))
        XCTAssertTrue(md.contains("| 1 | left | 12 reps | 5 kg per hand | RIR 1 |"))
    }

    func testSessionMarkdownRowingDownsamplesPerMinute() {
        let md = SessionMarkdown.render(rowing, catalogue: catalogue)
        XCTAssertTrue(md.contains("Rowing: 4000 m, in 20:00, avg HR 115 bpm, 16 min in zone, 200 kcal (console)"))
        XCTAssertTrue(md.contains("| Minute | heart_rate (bpm, polar_h10) |"))
        XCTAssertTrue(md.contains("| 0 | 100 |"))
        XCTAssertTrue(md.contains("| 2 | 120 |"))
        XCTAssertFalse(md.contains("| 3 |"))
    }

    func testLogCSVRowsAndQuoting() {
        let csv = LogCSV.render(sessions: [rowing, weights], catalogue: catalogue)
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertTrue(lines[0].hasPrefix("session_id,date,type,exercise,side,reps,seconds,meters,load_kg,rir,rpe,rest_s,tags,notes"))
        XCTAssertEqual(lines.filter { !$0.isEmpty }.count, 1 + 3 + 1)
        XCTAssertTrue(lines[1].hasPrefix("2026-11-05-0730-weights,2026-11-05 07:30,weights,Goblet squat,both,10,,,11.53,2,,90,heels raised,\"felt good, deep\",ex-goblet-squat,set"))
        XCTAssertTrue(lines[3].contains(",\"said \"\"ouch\"\"\","))
        XCTAssertTrue(lines[4].hasPrefix("2026-11-06-0700-rowing,2026-11-06 07:30,rowing,,,,1200,4000,"))
        XCTAssertTrue(lines[4].contains("session_summary,1200,4000,115,,16,"))
        XCTAssertEqual(LogCSV.quote("a\nb"), "\"a\nb\"")
        XCTAssertEqual(LogCSV.quote("plain"), "plain")
    }

    func testDigest() {
        let now = start + 2 * 86_400
        let days = [DaySnapshot(date: "2026-11-05", totals: ["protein_g": 120]),
                    DaySnapshot(date: "2026-11-06", totals: ["protein_g": 140])]
        let advice = [AdviceNote(id: "2026-11-01-zone-2", title: "More zone 2", date: start - 4 * 86_400, status: .open),
                      AdviceNote(id: "2026-10-01-old", title: "Old", date: start - 30 * 86_400, status: .done)]
        let md = Digest.render(catalogue: catalogue, sessions: [weights, rowing], days: days, advice: advice, now: now)
        XCTAssertTrue(md.contains("| t-zone2 | minutes_in_zone (Zone 2) | 175 per week | 16 | 4 | missed |"))
        XCTAssertTrue(md.contains("| t-protein | protein_g | 130 per day | 130 | 130 | met |"))
        XCTAssertTrue(md.contains("| Goblet squat | 11.53 kg × 10 | 11.53 kg × 10 |  | – |"))
        XCTAssertTrue(md.contains("- 2026-11-01 More zone 2 (`advice/2026-11-01-zone-2.md`)"))
        XCTAssertFalse(md.contains("Old"))
        XCTAssertFalse(md.contains("No session for"))
    }

    func testDigestFlags() {
        let now = start + 6 * 86_400
        let md = Digest.render(catalogue: catalogue, sessions: [weights], days: [], advice: [], now: now)
        XCTAssertTrue(md.contains("No session for 6 days (last 2026-11-05)."))
        XCTAssertTrue(md.contains("Target `t-zone2` (minutes_in_zone (Zone 2) 175 per week) missed 3 weeks running."))
        XCTAssertFalse(md.contains("Target `t-protein`"))
    }

    func testDocsCoverEveryFile() {
        let readme = ReadmeDoc.render(), schema = SchemaDoc.render()
        for path in [StoreLayout.schema, StoreLayout.digest, StoreLayout.logCSV, StoreLayout.adviceStatus, StoreLayout.bodyMeasures]
            + StoreLayout.catalogueFiles {
            XCTAssertTrue(readme.contains("`\(path)`"), "README missing \(path)")
        }
        for path in StoreLayout.catalogueFiles + [StoreLayout.adviceStatus, StoreLayout.bodyMeasures, StoreLayout.logCSV] {
            XCTAssertTrue(schema.contains("## \(path)"), "schema missing \(path)")
        }
        XCTAssertTrue(readme.contains("advice/<YYYY-MM-DD>-<topic>.md"))
        for field in ["rest_before_seconds", "variant_tags", "too_light_reps_above", "per_100g", "hr_source", "pace_s_per_500m"] {
            XCTAssertTrue(schema.contains(field), "schema missing \(field)")
        }
    }

    func testDayBuilder() {
        let foods = [Food(id: "f-oats", name: "Oats", per100g: ["energy_kcal": 380, "protein_g": 13])]
        let intake = [Intake(id: "i1", foodId: "f-oats", grams: 50), Intake(id: "i2", foodId: "f-missing", grams: 10)]
        let targets = [Target(id: "t-p", metric: "protein_g", value: 6),
                       Target(id: "t-steps", metric: "steps", value: 10_000),
                       Target(id: "t-w", metric: "minutes_in_zone", period: .week, value: 175)]
        let day = DayBuilder.build(date: "2026-11-05", intake: intake, foods: foods, metrics: ["steps": 8000], targets: targets)
        XCTAssertEqual(day.totals["energy_kcal"], 190)
        XCTAssertEqual(day.totals["protein_g"], 6.5)
        XCTAssertEqual(day.targets, [TargetProgress(targetId: "t-p", value: 6.5, target: 6, met: true),
                                     TargetProgress(targetId: "t-steps", value: 8000, target: 10_000, met: false)])
    }
}
