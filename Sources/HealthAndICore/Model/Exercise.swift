import Foundation

public struct Exercise: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var pattern: String?
    public var unilateral: Bool
    public var measure: Measure
    public var equipmentIds: [String]
    public var defaultRestSeconds: Int?
    public var targetRepMin: Int?
    public var targetRepMax: Int?
    public var notes: String?
    public var enabled: Bool

    public init(id: String, name: String, pattern: String? = nil, unilateral: Bool = false, measure: Measure = .reps,
                equipmentIds: [String] = [], defaultRestSeconds: Int? = nil, targetRepMin: Int? = nil,
                targetRepMax: Int? = nil, notes: String? = nil, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.unilateral = unilateral
        self.measure = measure
        self.equipmentIds = equipmentIds
        self.defaultRestSeconds = defaultRestSeconds
        self.targetRepMin = targetRepMin
        self.targetRepMax = targetRepMax
        self.notes = notes
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case id, name, pattern, unilateral, measure, equipmentIds = "equipment_ids"
        case defaultRestSeconds = "default_rest_seconds", targetRepMin = "target_rep_min"
        case targetRepMax = "target_rep_max", notes, enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        pattern = try c.opt(.pattern)
        unilateral = try c.val(.unilateral, false)
        measure = try c.val(.measure, .reps)
        equipmentIds = try c.val(.equipmentIds, [])
        defaultRestSeconds = try c.opt(.defaultRestSeconds)
        targetRepMin = try c.opt(.targetRepMin)
        targetRepMax = try c.opt(.targetRepMax)
        notes = try c.opt(.notes)
        enabled = try c.val(.enabled, true)
    }
}

public struct Zone: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var lower: Double
    public var upper: Double

    public init(name: String, lower: Double = 0, upper: Double = 0) {
        self.name = name
        self.lower = lower
        self.upper = upper
    }

    enum CodingKeys: String, CodingKey { case name, lower, upper }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        lower = try c.val(.lower, 0)
        upper = try c.val(.upper, 0)
    }
}

public struct ZoneSet: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var metric: ZoneMetric
    public var zones: [Zone]

    public init(id: String, name: String, metric: ZoneMetric = .heartRate, zones: [Zone] = []) {
        self.id = id
        self.name = name
        self.metric = metric
        self.zones = zones
    }

    enum CodingKeys: String, CodingKey { case id, name, metric, zones }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        metric = try c.val(.metric, .heartRate)
        zones = try c.val(.zones, [])
    }

    /// First zone whose inclusive [lower, upper] range contains `value`.
    public func zone(for value: Double) -> Zone? {
        zones.first { value >= $0.lower && value <= $0.upper }
    }

    public func zone(named name: String) -> Zone? {
        zones.first { $0.name == name }
    }
}

public struct Target: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    /// "minutes_in_zone", "energy_kcal", "protein_g", ... (free).
    public var metric: String
    public var period: Period
    public var value: Double
    public var zoneSetId: String?
    public var zoneName: String?
    public var enabled: Bool

    public init(id: String, metric: String = "", period: Period = .day, value: Double = 0,
                zoneSetId: String? = nil, zoneName: String? = nil, enabled: Bool = true) {
        self.id = id
        self.metric = metric
        self.period = period
        self.value = value
        self.zoneSetId = zoneSetId
        self.zoneName = zoneName
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case id, metric, period, value, zoneSetId = "zone_set_id", zoneName = "zone_name", enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        metric = try c.val(.metric, "")
        period = try c.val(.period, .day)
        value = try c.val(.value, 0)
        zoneSetId = try c.opt(.zoneSetId)
        zoneName = try c.opt(.zoneName)
        enabled = try c.val(.enabled, true)
    }
}
