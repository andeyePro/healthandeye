# HealthAndICore API contract (binding for all agents)

Pure Swift, Foundation only, no third-party deps, Swift 6 language mode, everything `Sendable`,
`Codable`, `Equatable`, `Hashable` where sensible. Ids are human-readable `String` slugs
(e.g. `ex-goblet-squat`, `eq-woodrower`), never UUIDs, so Claude can edit files by hand.
JSON encoding: `JSONEncoder` with `.prettyPrinted, .sortedKeys, .withoutEscapingSlashes`,
dates ISO 8601, keys snake_case via `.convertToSnakeCase`. Unknown keys tolerated; every
optional field decodes as nil when absent (NO required fields beyond `id`/`name`).

## Model (Sources/HealthAndICore/Model/*.swift)  — owner: core-model
```swift
public enum Source: String, Codable, Sendable { case polarH10 = "polar_h10", appleWatch = "apple_watch", machine, manual, healthKit = "health_kit", estimate }
public enum Units: String, Codable { case metric, imperial }
public enum Sex: String, Codable { case female, male, other }
public enum MaxHRFormula: String, Codable { case fox = "220_minus_age", tanaka, measured }
public struct Profile: Codable, Equatable, Sendable { heightCm, dateOfBirth, sex, maxHR, maxHRFormula, restingHR, units, timeZone, bodyMassKg — all optional; `func resolvedMaxHR(on: Date) -> Int?` }
public struct Equipment { id, name, kind: String (rower|bar|plate|collar|bench|dumbbell|band|other), massKg: Double?, quantity: Int?, limits: [String: Double] (e.g. "dumbbell_max_kg", "user_max_kg", "resistance_min", "resistance_max"), connection: Connection? { bleName: String?, protocolName: String? ("ftms"), hrRelay: Bool? }, quirks: [String], notes: String?, enabled: Bool (default true) }
public struct LoadPart { equipmentId: String, count: Int }
public struct Load { parts: [LoadPart], fixedKg: Double?, perHand: Bool (default true), label: String? }
public enum Measure: String, Codable { case reps, time, distance, strokes }
public struct Exercise { id, name, pattern: String?, unilateral: Bool, measure: Measure, equipmentIds: [String], defaultRestSeconds: Int?, targetRepMin: Int?, targetRepMax: Int?, notes, enabled }
public enum ZoneMetric: String, Codable { case heartRate = "heart_rate", power }
public struct Zone { name: String, lower: Double, upper: Double }
public struct ZoneSet { id, name, metric: ZoneMetric, zones: [Zone]; func zone(for value: Double) -> Zone? }
public enum Period: String, Codable { case day, week }
public struct Target { id, metric: String ("minutes_in_zone", "energy_kcal", "protein_g", ... free), period: Period, value: Double, zoneSetId: String?, zoneName: String?, enabled }
public enum Side: String, Codable { case left, right, both }
public struct SetEntry { id, exerciseId, side: Side, reps: Int?, seconds: Double?, meters: Double?, load: Load?, rir: Double?, rpe: Double?, restBeforeSeconds: Double?, restInterrupted: Bool?, variantTags: [String], notes: String?, timestamp: Date? }
public struct Sample { t: Double (seconds from session start), v: Double }
public struct IntervalSeries { metric: String ("heart_rate","stroke_rate","pace_s_per_500m","distance_m","resistance","power_w","energy_kcal","stroke_count"), unit: String, source: Source, samples: [Sample] }
public struct Session { id, start: Date, end: Date?, type: String ("rowing","weights","other"...), notes: String?, healthKitWorkoutId: String?, hrSource: Source?, equipmentIds: [String], sets: [SetEntry], intervals: [IntervalSeries], summary: [String: Double] (free: "distance_m","avg_hr","minutes_in_zone", "energy_kcal_hr","energy_kcal_console") }
public struct Food { id, name, per100g: [String: Double] ("energy_kcal","protein_g",...), servings: [Serving{ name, grams }] }
public struct Intake { id, foodId, grams: Double, time: Date }
public struct BodyMeasure { id, metric: String ("weight_kg","body_fat_pct","waist_cm"...), value: Double, time: Date, source: Source }
public enum AdviceStatus: String, Codable { case open, done, rejected }
public struct AdviceNote { id (= file stem), title, body: String, date: Date, status: AdviceStatus }
public enum Module: String, Codable, CaseIterable { case rowing, weights, nutrition, body, healthKitRead = "health_kit_read", healthKitWrite = "health_kit_write", export, advice }
public enum EffortScale: String, Codable { case rir, rpe }
public struct ProgressionRules { enabled: Bool, tooLightRepsAbove: Int (default 3 above target max), tooLightRirAtLeast: Double (default 3), underWarmedRepRise: Int (default 2) }
public struct Settings { modules: [String: Bool] (Module raw values; absent = true for weights/export, false otherwise), effortScale: EffortScale (.rir), setNotation: String ("reps@RIR"), hudTiles: [String] (ordered, default ["heart_rate","zone","stroke_rate","pace","distance","resistance","elapsed"]), progression: ProgressionRules, zoneCues: Bool, energyPrefersHR: Bool }
public struct Catalogue { profile: Profile, equipment: [Equipment], exercises: [Exercise], zoneSets: [ZoneSet], targets: [Target], foods: [Food], settings: Settings; static var empty }
public struct DaySnapshot { date: String (YYYY-MM-DD), metrics: [String: Double], intake: [Intake], totals: [String: Double], targets: [TargetProgress{ targetId, value, target, met }] }
```

## Load builder — owner core-model
`public enum LoadBuilder { static func totalKg(_ load: Load, catalogue: Catalogue) -> Double?; static func breakdown(...) -> [(name: String, count: Int, kg: Double)]; static func limitWarnings(load:, exercise:, catalogue:) -> [String] }`

## Store — owner core-model  (Sources/HealthAndICore/Store/)
The on-disk folder IS the export folder. Layout (`StoreLayout` constants):
```
README.md  schema.md  digest.md  log.csv
catalogue/profile.json equipment.json exercises.json zones.json targets.json foods.json settings.json
sessions/YYYY/YYYY-MM-DD-HHMM-<type>.json  (+ .md sibling rendered by Export)
daily/YYYY/YYYY-MM-DD.json
body/measures.json
advice/<anything>.md  (written by Claude, read-only to app)  advice/status.json {"<stem>": "open|done|rejected"}
```
`public final class FileStore: @unchecked Sendable { init(root: URL); func loadCatalogue() throws -> Catalogue; func saveCatalogue(_:) throws; func reloadCatalogueIfChanged() throws -> CatalogueDiff? (compares file mtimes/hashes against last load, returns human-readable diff lines); func saveSession(_:) throws (also writes .md via SessionMarkdown); func loadSessions(year: Int?) throws -> [Session]; func loadAdvice() throws -> [AdviceNote]; func setAdviceStatus(id:, status:) throws; func saveDay(_:) throws; func writeDerived(catalogue:, sessions:) throws (README.md, schema.md, digest.md, log.csv) }`
`public struct CatalogueDiff { lines: [String]; isEmpty }`
`public enum StarterPack { static func load() -> Catalogue  // bundled JSON in StarterPack/ via Bundle.module resources }` — the package must declare `resources: [.copy("../../StarterPack")]`? NO: put the starter JSON under `Sources/HealthAndICore/Resources/StarterPack/` and declare `.process("Resources")`; keep a symlink-free copy nowhere else.

## Rowing — owner core-rowing (Sources/HealthAndICore/Rowing/)
`public struct FTMSRowerData { strokeRate: Double?, strokeCount: Int?, averageStrokeRate: Double?, totalDistanceM: Int?, instantaneousPaceSPer500m: Int?, averagePace: Int?, instantaneousPowerW: Int?, averagePowerW: Int?, resistanceLevel: Int?, totalEnergyKcal: Int?, energyPerHour: Int?, energyPerMinute: Int?, heartRate: Int?, metabolicEquivalent: Double?, elapsedSeconds: Int?, remainingSeconds: Int?; static func parse(_ data: Data) -> FTMSRowerData? }` per FTMS 1.0 §4.9 (flags 16-bit; "more data" bit 0 INVERTED meaning: when bit0 is 0 the stroke rate/count fields are present).
`public struct FTMSFeature { fitnessMachineFeatures: UInt32, targetSettingFeatures: UInt32; supportsResistanceTarget: Bool ... parse }`
`public enum FTMSControlPoint { static func requestControl() -> Data; static func setResistanceLevel(_ level: Double) -> Data (op 0x04, uint8 0.1 resolution); static func start() -> Data; static func stop() -> Data; static func parseResponse(_ data: Data) -> (op: UInt8, result: UInt8)? }`
`public enum FTMSUUID { static let service = "1826", rowerData = "2AD1", feature = "2ACC", controlPoint = "2AD9", status = "2ADA", trainingStatus = "2AD3", hrService = "180D", hrMeasurement = "2A37" }`
`public struct HeartRateMeasurement { bpm: Int, rrIntervals: [Double]; static func parse(_ data: Data) -> HeartRateMeasurement? }` (0x2A37 flags).
`public struct ZoneEngine { init(zoneSet: ZoneSet, zoneName: String); func state(for hr: Double) -> ZoneState (.below/.inBand/.above); func cue(previous:, current:) -> ZoneCue? }` with hysteresis + minimum seconds between cues (configurable).
`public struct SessionRecorder { init(start: Date); mutating func add(metric:, unit:, source:, value:, at: Date); func series() -> [IntervalSeries]; func summary(zoneSet:, zoneName:) -> [String: Double] (distance_m, avg_hr, max_hr, minutes_in_zone, avg_stroke_rate, avg_pace, energy_kcal_console) }`
`public enum EnergyEstimator { static func kcal(hrSeries: IntervalSeries, profile: Profile) -> Double? }` Keytel 2005 (needs sex, age, mass; fallback nil).
`public struct ResistanceController { PI controller: init(targetHR:, kp:, ki:, min:, max:); mutating func step(hr:, dt:) -> Double }` — pure, unused by apps in v1.

## Export / Import / Hints — owner core-export (Sources/HealthAndICore/Export/, Import/, Hints/)
`public enum SessionMarkdown { static func render(_ session: Session, catalogue: Catalogue) -> String }`
`public enum Digest { static func render(catalogue:, sessions:, days: [DaySnapshot], advice: [AdviceNote], now: Date) -> String }` (last 7 / 28 days vs targets, trends, flags, open advice)
`public enum LogCSV { static func render(sessions:, catalogue:) -> String }` one row per set and one per rowing session.
`public enum SchemaDoc { static func render() -> String }`, `public enum ReadmeDoc { static func render() -> String }` — describe every file/field/unit so any reader orients.
`public enum ProgressionAdvisor { static func hints(for session: Session, history: [Session], catalogue: Catalogue) -> [Hint{ exerciseId, kind: String, message }] }`
`public struct TrainingLogCSVImporter { init(columnMap: [String: String] = defaults); func parse(csv: String, catalogue: Catalogue) -> (sessions: [Session], newExercises: [Exercise], warnings: [String]) }` — tolerant: header-driven, date/exercise/side/reps/load/RIR/notes columns, unknown exercises auto-created.
`public enum DayBuilder { static func build(date:, intake:, foods:, metrics:, targets:) -> DaySnapshot }`

## Apps (Apps/Shared, Apps/iOS, Apps/Watch) — owners app-services, app-ios, app-watch
Apps compile against the package product `HealthAndICore` (XcodeGen local package). Shared services in `Apps/Shared/Services`: `StoreController` (@Observable; owns FileStore at the chosen folder; default = app's iCloud Drive container `Documents/` if available else local Documents; security-scoped bookmark for a user-picked folder), `BLEManager` (CoreBluetooth; scans FTMS + HR services, connects, publishes FTMSRowerData + HR, writes control point only if `settings.modules["closed_loop"] == true`), `HealthKitService` (per-permission requests on module toggle; write workouts/HR/energy; read listed metrics; never overwrite), `WatchBridge` (WatchConnectivity; live HUD snapshot phone→watch, logged sets watch→phone).
