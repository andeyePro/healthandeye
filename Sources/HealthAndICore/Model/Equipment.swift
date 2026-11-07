import Foundation

public struct Connection: Codable, Equatable, Hashable, Sendable {
    public var bleName: String?
    /// e.g. "ftms".
    public var protocolName: String?
    public var hrRelay: Bool?

    public init(bleName: String? = nil, protocolName: String? = nil, hrRelay: Bool? = nil) {
        self.bleName = bleName
        self.protocolName = protocolName
        self.hrRelay = hrRelay
    }

    enum CodingKeys: String, CodingKey {
        case bleName = "ble_name", protocolName = "protocol_name", hrRelay = "hr_relay"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bleName = try c.opt(.bleName)
        protocolName = try c.opt(.protocolName)
        hrRelay = try c.opt(.hrRelay)
    }
}

public struct Equipment: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// rower | bar | plate | collar | bench | dumbbell | band | other (free text).
    public var kind: String
    public var massKg: Double?
    public var quantity: Int?
    /// e.g. "dumbbell_max_kg", "user_max_kg", "resistance_min", "resistance_max", "per_sleeve_max".
    public var limits: [String: Double]
    public var connection: Connection?
    public var quirks: [String]
    public var notes: String?
    public var enabled: Bool

    public init(id: String, name: String, kind: String = "other", massKg: Double? = nil, quantity: Int? = nil,
                limits: [String: Double] = [:], connection: Connection? = nil, quirks: [String] = [],
                notes: String? = nil, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.massKg = massKg
        self.quantity = quantity
        self.limits = limits
        self.connection = connection
        self.quirks = quirks
        self.notes = notes
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case id, name, kind, massKg = "mass_kg", quantity, limits, connection, quirks, notes, enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.val(.kind, "other")
        massKg = try c.opt(.massKg)
        quantity = try c.opt(.quantity)
        limits = try c.val(.limits, [:])
        connection = try c.opt(.connection)
        quirks = try c.val(.quirks, [])
        notes = try c.opt(.notes)
        enabled = try c.val(.enabled, true)
    }
}

public struct LoadPart: Codable, Equatable, Hashable, Sendable {
    public var equipmentId: String
    public var count: Int

    public init(equipmentId: String, count: Int = 1) {
        self.equipmentId = equipmentId
        self.count = count
    }

    enum CodingKeys: String, CodingKey { case equipmentId = "equipment_id", count }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        equipmentId = try c.val(.equipmentId, "")
        count = try c.val(.count, 1)
    }
}

public struct Load: Codable, Equatable, Hashable, Sendable {
    public var parts: [LoadPart]
    public var fixedKg: Double?
    public var perHand: Bool
    public var label: String?

    public init(parts: [LoadPart] = [], fixedKg: Double? = nil, perHand: Bool = true, label: String? = nil) {
        self.parts = parts
        self.fixedKg = fixedKg
        self.perHand = perHand
        self.label = label
    }

    enum CodingKeys: String, CodingKey { case parts, fixedKg = "fixed_kg", perHand = "per_hand", label }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        parts = try c.val(.parts, [])
        fixedKg = try c.opt(.fixedKg)
        perHand = try c.val(.perHand, true)
        label = try c.opt(.label)
    }
}
