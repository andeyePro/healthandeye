import Foundation

/// PI controller that holds HR at a target by moving resistance (after EricBriscoe/heartdrive).
/// HR above target lowers resistance. Pure: no I/O, the caller feeds HR and elapsed time.
public struct ResistanceController: Sendable, Equatable {
    public var targetHR: Double
    public var kp: Double
    public var ki: Double
    public var min: Double
    public var max: Double
    public private(set) var integral: Double = 0
    public private(set) var output: Double

    /// `initial` is the resistance returned when HR sits on target with no accumulated error.
    public init(targetHR: Double, kp: Double, ki: Double, min: Double, max: Double, initial: Double? = nil) {
        self.targetHR = targetHR
        self.kp = kp
        self.ki = ki
        self.min = min
        self.max = max
        self.output = Swift.min(max, Swift.max(min, initial ?? min))
        self.bias = output
    }

    private let bias: Double

    public mutating func step(hr: Double, dt: Double) -> Double {
        let error = targetHR - hr
        let candidate = integral + error * dt
        let raw = bias + kp * error + ki * candidate
        // Conditional integration: stop accumulating while saturated, so the integral
        // does not wind up during a long excursion and overshoot on the way back.
        if raw >= min && raw <= max {
            integral = candidate
        }
        output = Swift.min(max, Swift.max(min, bias + kp * error + ki * integral))
        return output
    }
}
