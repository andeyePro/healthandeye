import Foundation

public struct ProgressionRules: Codable, Equatable, Hashable, Sendable {
    public var enabled: Bool
    /// Flag "too light" when reps exceed the exercise's target max by more than this.
    public var tooLightRepsAbove: Int
    public var tooLightRirAtLeast: Double
    /// Flag "under-warmed" when reps rise across sets by at least this.
    public var underWarmedRepRise: Int

    public init(enabled: Bool = true, tooLightRepsAbove: Int = 3, tooLightRirAtLeast: Double = 3,
                underWarmedRepRise: Int = 2) {
        self.enabled = enabled
        self.tooLightRepsAbove = tooLightRepsAbove
        self.tooLightRirAtLeast = tooLightRirAtLeast
        self.underWarmedRepRise = underWarmedRepRise
    }

    enum CodingKeys: String, CodingKey {
        case enabled, tooLightRepsAbove = "too_light_reps_above", tooLightRirAtLeast = "too_light_rir_at_least"
        case underWarmedRepRise = "under_warmed_rep_rise"
    }

    public init(from decoder: Decoder) throws {
        let d = ProgressionRules()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.val(.enabled, d.enabled)
        tooLightRepsAbove = try c.val(.tooLightRepsAbove, d.tooLightRepsAbove)
        tooLightRirAtLeast = try c.val(.tooLightRirAtLeast, d.tooLightRirAtLeast)
        underWarmedRepRise = try c.val(.underWarmedRepRise, d.underWarmedRepRise)
    }
}

public struct Settings: Codable, Equatable, Hashable, Sendable {
    public static let defaultHudTiles = ["heart_rate", "zone", "stroke_rate", "pace", "distance", "resistance", "elapsed"]
    public static let defaultOnModules: Set<String> = [Module.weights.rawValue, Module.export.rawValue]

    /// Keyed by `Module` raw values (other keys such as "closed_loop" allowed). Use `isEnabled` to read.
    public var modules: [String: Bool]
    public var effortScale: EffortScale
    public var setNotation: String
    public var hudTiles: [String]
    public var progression: ProgressionRules
    public var zoneCues: Bool
    public var energyPrefersHR: Bool

    public init(modules: [String: Bool] = [:], effortScale: EffortScale = .rir, setNotation: String = "reps@RIR",
                hudTiles: [String] = Settings.defaultHudTiles, progression: ProgressionRules = ProgressionRules(),
                zoneCues: Bool = true, energyPrefersHR: Bool = true) {
        self.modules = modules
        self.effortScale = effortScale
        self.setNotation = setNotation
        self.hudTiles = hudTiles
        self.progression = progression
        self.zoneCues = zoneCues
        self.energyPrefersHR = energyPrefersHR
    }

    enum CodingKeys: String, CodingKey {
        case modules, effortScale = "effort_scale", setNotation = "set_notation", hudTiles = "hud_tiles"
        case progression, zoneCues = "zone_cues", energyPrefersHR = "energy_prefers_hr"
    }

    public init(from decoder: Decoder) throws {
        let d = Settings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modules = try c.val(.modules, d.modules)
        effortScale = try c.val(.effortScale, d.effortScale)
        setNotation = try c.val(.setNotation, d.setNotation)
        hudTiles = try c.val(.hudTiles, d.hudTiles)
        progression = try c.val(.progression, d.progression)
        zoneCues = try c.val(.zoneCues, d.zoneCues)
        energyPrefersHR = try c.val(.energyPrefersHR, d.energyPrefersHR)
    }

    /// Absent keys default to on for weights and export, off otherwise.
    public func isEnabled(_ module: Module) -> Bool {
        isEnabled(module.rawValue)
    }

    public func isEnabled(_ key: String) -> Bool {
        modules[key] ?? Settings.defaultOnModules.contains(key)
    }

    public mutating func setEnabled(_ module: Module, _ on: Bool) {
        modules[module.rawValue] = on
    }
}
