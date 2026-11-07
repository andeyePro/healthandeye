import Foundation

public struct Profile: Codable, Equatable, Hashable, Sendable {
    public var heightCm: Double?
    public var dateOfBirth: Date?
    public var sex: Sex?
    public var maxHR: Int?
    public var maxHRFormula: MaxHRFormula?
    public var restingHR: Int?
    public var units: Units?
    /// IANA identifier, e.g. "Europe/London".
    public var timeZone: String?
    public var bodyMassKg: Double?

    public init(heightCm: Double? = nil, dateOfBirth: Date? = nil, sex: Sex? = nil, maxHR: Int? = nil,
                maxHRFormula: MaxHRFormula? = nil, restingHR: Int? = nil, units: Units? = nil,
                timeZone: String? = nil, bodyMassKg: Double? = nil) {
        self.heightCm = heightCm
        self.dateOfBirth = dateOfBirth
        self.sex = sex
        self.maxHR = maxHR
        self.maxHRFormula = maxHRFormula
        self.restingHR = restingHR
        self.units = units
        self.timeZone = timeZone
        self.bodyMassKg = bodyMassKg
    }

    enum CodingKeys: String, CodingKey {
        case heightCm = "height_cm", dateOfBirth = "date_of_birth", sex, maxHR = "max_hr"
        case maxHRFormula = "max_hr_formula", restingHR = "resting_hr", units, timeZone = "time_zone"
        case bodyMassKg = "body_mass_kg"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        heightCm = try c.opt(.heightCm)
        dateOfBirth = try c.opt(.dateOfBirth)
        sex = try c.opt(.sex)
        maxHR = try c.opt(.maxHR)
        maxHRFormula = try c.opt(.maxHRFormula)
        restingHR = try c.opt(.restingHR)
        units = try c.opt(.units)
        timeZone = try c.opt(.timeZone)
        bodyMassKg = try c.opt(.bodyMassKg)
    }

    public func age(on date: Date) -> Int? {
        guard let dob = dateOfBirth else { return nil }
        var cal = Calendar(identifier: .gregorian)
        if let id = timeZone, let tz = TimeZone(identifier: id) { cal.timeZone = tz }
        return cal.dateComponents([.year], from: dob, to: date).year
    }

    /// A stored max HR wins unless a formula other than `.measured` is chosen and an age is known.
    public func resolvedMaxHR(on date: Date) -> Int? {
        switch maxHRFormula {
        case .fox?:
            if let a = age(on: date) { return 220 - a }
        case .tanaka?:
            if let a = age(on: date) { return Int((208 - 0.7 * Double(a)).rounded()) }
        case .measured?, nil:
            break
        }
        return maxHR
    }
}
