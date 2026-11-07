import Foundation

public struct SetEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var exerciseId: String
    public var side: Side
    public var reps: Int?
    public var seconds: Double?
    public var meters: Double?
    public var load: Load?
    public var rir: Double?
    public var rpe: Double?
    public var restBeforeSeconds: Double?
    public var restInterrupted: Bool?
    public var variantTags: [String]
    public var notes: String?
    public var timestamp: Date?

    public init(id: String, exerciseId: String, side: Side = .both, reps: Int? = nil, seconds: Double? = nil,
                meters: Double? = nil, load: Load? = nil, rir: Double? = nil, rpe: Double? = nil,
                restBeforeSeconds: Double? = nil, restInterrupted: Bool? = nil, variantTags: [String] = [],
                notes: String? = nil, timestamp: Date? = nil) {
        self.id = id
        self.exerciseId = exerciseId
        self.side = side
        self.reps = reps
        self.seconds = seconds
        self.meters = meters
        self.load = load
        self.rir = rir
        self.rpe = rpe
        self.restBeforeSeconds = restBeforeSeconds
        self.restInterrupted = restInterrupted
        self.variantTags = variantTags
        self.notes = notes
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id, exerciseId = "exercise_id", side, reps, seconds, meters, load, rir, rpe
        case restBeforeSeconds = "rest_before_seconds", restInterrupted = "rest_interrupted"
        case variantTags = "variant_tags", notes, timestamp
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        exerciseId = try c.val(.exerciseId, "")
        side = try c.val(.side, .both)
        reps = try c.opt(.reps)
        seconds = try c.opt(.seconds)
        meters = try c.opt(.meters)
        load = try c.opt(.load)
        rir = try c.opt(.rir)
        rpe = try c.opt(.rpe)
        restBeforeSeconds = try c.opt(.restBeforeSeconds)
        restInterrupted = try c.opt(.restInterrupted)
        variantTags = try c.val(.variantTags, [])
        notes = try c.opt(.notes)
        timestamp = try c.opt(.timestamp)
    }
}

public struct Sample: Codable, Equatable, Hashable, Sendable {
    /// Seconds from session start.
    public var t: Double
    public var v: Double

    public init(t: Double, v: Double) {
        self.t = t
        self.v = v
    }

    enum CodingKeys: String, CodingKey { case t, v }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.val(.t, 0)
        v = try c.val(.v, 0)
    }
}

public struct IntervalSeries: Codable, Equatable, Hashable, Sendable {
    /// "heart_rate", "stroke_rate", "pace_s_per_500m", "distance_m", "resistance", "power_w", "energy_kcal", "stroke_count".
    public var metric: String
    public var unit: String
    public var source: Source
    public var samples: [Sample]

    public init(metric: String, unit: String = "", source: Source = .manual, samples: [Sample] = []) {
        self.metric = metric
        self.unit = unit
        self.source = source
        self.samples = samples
    }

    enum CodingKeys: String, CodingKey { case metric, unit, source, samples }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metric = try c.val(.metric, "")
        unit = try c.val(.unit, "")
        source = try c.val(.source, .manual)
        samples = try c.val(.samples, [])
    }
}

public struct Session: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var start: Date
    public var end: Date?
    /// "rowing", "weights", "other", ... (free).
    public var type: String
    public var notes: String?
    public var healthKitWorkoutId: String?
    public var hrSource: Source?
    public var equipmentIds: [String]
    public var sets: [SetEntry]
    public var intervals: [IntervalSeries]
    /// Free: "distance_m", "avg_hr", "minutes_in_zone", "energy_kcal_hr", "energy_kcal_console", ...
    public var summary: [String: Double]

    public init(id: String, start: Date = Date(), end: Date? = nil, type: String = "other", notes: String? = nil,
                healthKitWorkoutId: String? = nil, hrSource: Source? = nil, equipmentIds: [String] = [],
                sets: [SetEntry] = [], intervals: [IntervalSeries] = [], summary: [String: Double] = [:]) {
        self.id = id
        self.start = start
        self.end = end
        self.type = type
        self.notes = notes
        self.healthKitWorkoutId = healthKitWorkoutId
        self.hrSource = hrSource
        self.equipmentIds = equipmentIds
        self.sets = sets
        self.intervals = intervals
        self.summary = summary
    }

    enum CodingKeys: String, CodingKey {
        case id, start, end, type, notes, healthKitWorkoutId = "health_kit_workout_id", hrSource = "hr_source"
        case equipmentIds = "equipment_ids", sets, intervals, summary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        start = try c.val(.start, Date(timeIntervalSince1970: 0))
        end = try c.opt(.end)
        type = try c.val(.type, "other")
        notes = try c.opt(.notes)
        healthKitWorkoutId = try c.opt(.healthKitWorkoutId)
        hrSource = try c.opt(.hrSource)
        equipmentIds = try c.val(.equipmentIds, [])
        sets = try c.val(.sets, [])
        intervals = try c.val(.intervals, [])
        summary = try c.val(.summary, [:])
    }
}
