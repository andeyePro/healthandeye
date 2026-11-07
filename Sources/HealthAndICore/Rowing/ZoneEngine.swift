import Foundation

public enum ZoneState: String, Codable, Sendable {
    case below, inBand, above
}

public enum ZoneCue: String, Codable, Sendable {
    case goHarder, easeOff, backInBand
}

/// Classifies HR against one zone of a ZoneSet and decides when to cue the rower.
/// `update(hr:at:)` is the live entry point: it applies hysteresis (HR must pass the band edge
/// by `hysteresisBpm` to leave it) and suppresses cues closer together than `minSecondsBetweenCues`.
/// A suppressed change is cued once the gap has elapsed if the state still differs.
public struct ZoneEngine: Sendable {
    public let zone: Zone?
    public var hysteresisBpm: Double
    public var minSecondsBetweenCues: Double
    public private(set) var currentState: ZoneState?
    public private(set) var lastCuedState: ZoneState?
    public private(set) var lastCueAt: Date?

    public init(zoneSet: ZoneSet, zoneName: String, hysteresisBpm: Double = 2, minSecondsBetweenCues: Double = 10) {
        zone = zoneSet.zones.first { $0.name == zoneName }
        self.hysteresisBpm = hysteresisBpm
        self.minSecondsBetweenCues = minSecondsBetweenCues
    }

    /// Plain classification without hysteresis. An unknown zone name always reads as in band.
    public func state(for hr: Double) -> ZoneState {
        guard let zone else { return .inBand }
        if hr < zone.lower { return .below }
        if hr > zone.upper { return .above }
        return .inBand
    }

    /// Classification with hysteresis relative to the previous state.
    public func state(for hr: Double, previous: ZoneState?) -> ZoneState {
        guard let zone, previous == .inBand else { return state(for: hr) }
        if hr < zone.lower - hysteresisBpm { return .below }
        if hr > zone.upper + hysteresisBpm { return .above }
        return .inBand
    }

    public func cue(previous: ZoneState?, current: ZoneState) -> ZoneCue? {
        guard let previous, previous != current else { return nil }
        switch current {
        case .below: return .goHarder
        case .above: return .easeOff
        case .inBand: return .backInBand
        }
    }

    /// Feeds one HR reading. The first reading sets the baseline and never cues.
    public mutating func update(hr: Double, at time: Date) -> ZoneCue? {
        let newState = state(for: hr, previous: currentState)
        currentState = newState
        guard let cued = lastCuedState else {
            lastCuedState = newState
            return nil
        }
        if let last = lastCueAt, time.timeIntervalSince(last) < minSecondsBetweenCues { return nil }
        guard let result = cue(previous: cued, current: newState) else { return nil }
        lastCuedState = newState
        lastCueAt = time
        return result
    }
}
