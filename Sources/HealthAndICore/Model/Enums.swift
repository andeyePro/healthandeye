import Foundation

public enum Source: String, Codable, Sendable, Hashable, CaseIterable {
    case polarH10 = "polar_h10", appleWatch = "apple_watch", machine, manual, healthKit = "health_kit", estimate
}

public enum Units: String, Codable, Sendable, Hashable, CaseIterable { case metric, imperial }

public enum Sex: String, Codable, Sendable, Hashable, CaseIterable { case female, male, other }

public enum MaxHRFormula: String, Codable, Sendable, Hashable, CaseIterable {
    case fox = "220_minus_age", tanaka, measured
}

public enum Measure: String, Codable, Sendable, Hashable, CaseIterable { case reps, time, distance, strokes }

public enum ZoneMetric: String, Codable, Sendable, Hashable, CaseIterable {
    case heartRate = "heart_rate", power
}

public enum Period: String, Codable, Sendable, Hashable, CaseIterable { case day, week }

public enum Side: String, Codable, Sendable, Hashable, CaseIterable { case left, right, both }

public enum AdviceStatus: String, Codable, Sendable, Hashable, CaseIterable { case open, done, rejected }

public enum Module: String, Codable, Sendable, Hashable, CaseIterable {
    case rowing, weights, nutrition, body
    case healthKitRead = "health_kit_read", healthKitWrite = "health_kit_write"
    case export, advice
}

public enum EffortScale: String, Codable, Sendable, Hashable, CaseIterable { case rir, rpe }
