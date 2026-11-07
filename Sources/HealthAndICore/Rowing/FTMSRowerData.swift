import Foundation

/// FTMS 1.0 §4.9 Rower Data (0x2AD1). Each field is nil when absent from the packet,
/// cut off by truncation, or carrying the spec's "not available" sentinel.
public struct FTMSRowerData: Codable, Equatable, Hashable, Sendable {
    public var strokeRate: Double?
    public var strokeCount: Int?
    public var averageStrokeRate: Double?
    public var totalDistanceM: Int?
    public var instantaneousPaceSPer500m: Int?
    public var averagePace: Int?
    public var instantaneousPowerW: Int?
    public var averagePowerW: Int?
    public var resistanceLevel: Int?
    public var totalEnergyKcal: Int?
    public var energyPerHour: Int?
    public var energyPerMinute: Int?
    public var heartRate: Int?
    public var metabolicEquivalent: Double?
    public var elapsedSeconds: Int?
    public var remainingSeconds: Int?

    public init(
        strokeRate: Double? = nil, strokeCount: Int? = nil, averageStrokeRate: Double? = nil,
        totalDistanceM: Int? = nil, instantaneousPaceSPer500m: Int? = nil, averagePace: Int? = nil,
        instantaneousPowerW: Int? = nil, averagePowerW: Int? = nil, resistanceLevel: Int? = nil,
        totalEnergyKcal: Int? = nil, energyPerHour: Int? = nil, energyPerMinute: Int? = nil,
        heartRate: Int? = nil, metabolicEquivalent: Double? = nil,
        elapsedSeconds: Int? = nil, remainingSeconds: Int? = nil
    ) {
        self.strokeRate = strokeRate
        self.strokeCount = strokeCount
        self.averageStrokeRate = averageStrokeRate
        self.totalDistanceM = totalDistanceM
        self.instantaneousPaceSPer500m = instantaneousPaceSPer500m
        self.averagePace = averagePace
        self.instantaneousPowerW = instantaneousPowerW
        self.averagePowerW = averagePowerW
        self.resistanceLevel = resistanceLevel
        self.totalEnergyKcal = totalEnergyKcal
        self.energyPerHour = energyPerHour
        self.energyPerMinute = energyPerMinute
        self.heartRate = heartRate
        self.metabolicEquivalent = metabolicEquivalent
        self.elapsedSeconds = elapsedSeconds
        self.remainingSeconds = remainingSeconds
    }

    /// Returns nil only when the 16-bit flags field itself is missing.
    public static func parse(_ data: Data) -> FTMSRowerData? {
        var r = ByteReader(data)
        guard let flags = r.uint16() else { return nil }
        var out = FTMSRowerData()
        func has(_ bit: Int) -> Bool { flags & (1 << bit) != 0 }

        // Bit 0 is "More Data": stroke rate/count are present when it is CLEAR.
        if !has(0) {
            guard let v = r.uint8() else { return out }
            out.strokeRate = u8(v).map { Double($0) / 2 }
            guard let c = r.uint16() else { return out }
            out.strokeCount = u16(c)
        }
        if has(1) {
            guard let v = r.uint8() else { return out }
            out.averageStrokeRate = u8(v).map { Double($0) / 2 }
        }
        if has(2) {
            guard let v = r.uint24() else { return out }
            out.totalDistanceM = v == 0xFF_FFFF ? nil : Int(v)
        }
        if has(3) {
            guard let v = r.uint16() else { return out }
            out.instantaneousPaceSPer500m = u16(v)
        }
        if has(4) {
            guard let v = r.uint16() else { return out }
            out.averagePace = u16(v)
        }
        if has(5) {
            guard let v = r.sint16() else { return out }
            out.instantaneousPowerW = s16(v)
        }
        if has(6) {
            guard let v = r.sint16() else { return out }
            out.averagePowerW = s16(v)
        }
        if has(7) {
            guard let v = r.sint16() else { return out }
            out.resistanceLevel = s16(v)
        }
        if has(8) {
            guard let total = r.uint16() else { return out }
            out.totalEnergyKcal = u16(total)
            guard let perHour = r.uint16() else { return out }
            out.energyPerHour = u16(perHour)
            guard let perMinute = r.uint8() else { return out }
            out.energyPerMinute = u8(perMinute)
        }
        if has(9) {
            guard let v = r.uint8() else { return out }
            out.heartRate = u8(v)
        }
        if has(10) {
            guard let v = r.uint8() else { return out }
            out.metabolicEquivalent = u8(v).map { Double($0) / 10 }
        }
        if has(11) {
            guard let v = r.uint16() else { return out }
            out.elapsedSeconds = u16(v)
        }
        if has(12) {
            guard let v = r.uint16() else { return out }
            out.remainingSeconds = u16(v)
        }
        return out
    }

    private static func u8(_ v: UInt8) -> Int? { v == 0xFF ? nil : Int(v) }
    private static func u16(_ v: UInt16) -> Int? { v == 0xFFFF ? nil : Int(v) }
    /// FTMS marks an unavailable signed 16-bit field with 0x7FFF.
    private static func s16(_ v: Int16) -> Int? { v == Int16.max ? nil : Int(v) }
}
