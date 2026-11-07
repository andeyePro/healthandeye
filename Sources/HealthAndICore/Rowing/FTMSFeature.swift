import Foundation

/// FTMS Feature (0x2ACC): Fitness Machine Features then Target Setting Features, uint32 each.
public struct FTMSFeature: Codable, Equatable, Hashable, Sendable {
    public var fitnessMachineFeatures: UInt32
    public var targetSettingFeatures: UInt32

    public init(fitnessMachineFeatures: UInt32, targetSettingFeatures: UInt32) {
        self.fitnessMachineFeatures = fitnessMachineFeatures
        self.targetSettingFeatures = targetSettingFeatures
    }

    /// Needs the first bitfield; a missing target-setting field reads as "nothing settable".
    public static func parse(_ data: Data) -> FTMSFeature? {
        var r = ByteReader(data)
        guard let machine = r.uint32() else { return nil }
        return FTMSFeature(fitnessMachineFeatures: machine, targetSettingFeatures: r.uint32() ?? 0)
    }

    private func machine(_ bit: Int) -> Bool { fitnessMachineFeatures & (1 << bit) != 0 }
    private func target(_ bit: Int) -> Bool { targetSettingFeatures & (1 << bit) != 0 }

    public var supportsCadence: Bool { machine(1) }
    public var supportsTotalDistance: Bool { machine(2) }
    public var supportsPace: Bool { machine(5) }
    public var supportsResistanceLevel: Bool { machine(7) }
    public var supportsExpendedEnergy: Bool { machine(9) }
    public var supportsHeartRate: Bool { machine(10) }
    public var supportsPower: Bool { machine(14) }

    public var supportsResistanceTarget: Bool { target(2) }
    public var supportsPowerTarget: Bool { target(3) }
    public var supportsHeartRateTarget: Bool { target(4) }
}
