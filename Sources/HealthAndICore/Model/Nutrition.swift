import Foundation

public struct Serving: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var grams: Double

    public init(name: String, grams: Double = 0) {
        self.name = name
        self.grams = grams
    }

    enum CodingKeys: String, CodingKey { case name, grams }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        grams = try c.val(.grams, 0)
    }
}

public struct Food: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// "energy_kcal", "protein_g", ... per 100 g.
    public var per100g: [String: Double]
    public var servings: [Serving]

    public init(id: String, name: String, per100g: [String: Double] = [:], servings: [Serving] = []) {
        self.id = id
        self.name = name
        self.per100g = per100g
        self.servings = servings
    }

    enum CodingKeys: String, CodingKey { case id, name, per100g = "per_100g", servings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        per100g = try c.val(.per100g, [:])
        servings = try c.val(.servings, [])
    }
}

public struct Intake: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var foodId: String
    public var grams: Double
    public var time: Date

    public init(id: String, foodId: String, grams: Double = 0, time: Date = Date()) {
        self.id = id
        self.foodId = foodId
        self.grams = grams
        self.time = time
    }

    enum CodingKeys: String, CodingKey { case id, foodId = "food_id", grams, time }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        foodId = try c.val(.foodId, "")
        grams = try c.val(.grams, 0)
        time = try c.val(.time, Date(timeIntervalSince1970: 0))
    }
}

public struct BodyMeasure: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    /// "weight_kg", "body_fat_pct", "waist_cm", ...
    public var metric: String
    public var value: Double
    public var time: Date
    public var source: Source

    public init(id: String, metric: String, value: Double = 0, time: Date = Date(), source: Source = .manual) {
        self.id = id
        self.metric = metric
        self.value = value
        self.time = time
        self.source = source
    }

    enum CodingKeys: String, CodingKey { case id, metric, value, time, source }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        metric = try c.val(.metric, "")
        value = try c.val(.value, 0)
        time = try c.val(.time, Date(timeIntervalSince1970: 0))
        source = try c.val(.source, .manual)
    }
}

public struct TargetProgress: Codable, Equatable, Hashable, Sendable {
    public var targetId: String
    public var value: Double
    public var target: Double
    public var met: Bool

    public init(targetId: String, value: Double = 0, target: Double = 0, met: Bool = false) {
        self.targetId = targetId
        self.value = value
        self.target = target
        self.met = met
    }

    enum CodingKeys: String, CodingKey { case targetId = "target_id", value, target, met }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        targetId = try c.val(.targetId, "")
        value = try c.val(.value, 0)
        target = try c.val(.target, 0)
        met = try c.val(.met, false)
    }
}

public struct DaySnapshot: Codable, Equatable, Hashable, Sendable {
    /// YYYY-MM-DD.
    public var date: String
    public var metrics: [String: Double]
    public var intake: [Intake]
    public var totals: [String: Double]
    public var targets: [TargetProgress]

    public init(date: String, metrics: [String: Double] = [:], intake: [Intake] = [], totals: [String: Double] = [:],
                targets: [TargetProgress] = []) {
        self.date = date
        self.metrics = metrics
        self.intake = intake
        self.totals = totals
        self.targets = targets
    }

    enum CodingKeys: String, CodingKey { case date, metrics, intake, totals, targets }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.val(.date, "")
        metrics = try c.val(.metrics, [:])
        intake = try c.val(.intake, [])
        totals = try c.val(.totals, [:])
        targets = try c.val(.targets, [])
    }
}
