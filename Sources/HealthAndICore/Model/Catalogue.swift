import Foundation

public struct Catalogue: Codable, Equatable, Hashable, Sendable {
    public var profile: Profile
    public var equipment: [Equipment]
    public var exercises: [Exercise]
    public var zoneSets: [ZoneSet]
    public var targets: [Target]
    public var foods: [Food]
    public var settings: Settings

    public static let empty = Catalogue()

    public init(profile: Profile = Profile(), equipment: [Equipment] = [], exercises: [Exercise] = [],
                zoneSets: [ZoneSet] = [], targets: [Target] = [], foods: [Food] = [], settings: Settings = Settings()) {
        self.profile = profile
        self.equipment = equipment
        self.exercises = exercises
        self.zoneSets = zoneSets
        self.targets = targets
        self.foods = foods
        self.settings = settings
    }

    enum CodingKeys: String, CodingKey {
        case profile, equipment, exercises, zoneSets = "zone_sets", targets, foods, settings
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try c.val(.profile, Profile())
        equipment = try c.val(.equipment, [])
        exercises = try c.val(.exercises, [])
        zoneSets = try c.val(.zoneSets, [])
        targets = try c.val(.targets, [])
        foods = try c.val(.foods, [])
        settings = try c.val(.settings, Settings())
    }

    public func equipment(id: String) -> Equipment? { equipment.first { $0.id == id } }
    public func exercise(id: String) -> Exercise? { exercises.first { $0.id == id } }
    public func zoneSet(id: String) -> ZoneSet? { zoneSets.first { $0.id == id } }
    public func food(id: String) -> Food? { foods.first { $0.id == id } }
}
