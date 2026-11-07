import Foundation
import Observation
import HealthAndICore

/// Rest between sets. Target comes from the exercise; the actual rest (wall time until the next
/// set) and whether it was interrupted are recorded onto the next SetEntry.
@Observable @MainActor
final class RestTimer {
    static let defaultSeconds = 90

    var exerciseId: String?
    var targetSeconds = RestTimer.defaultSeconds
    var startedAt: Date?
    var elapsed: TimeInterval = 0
    var interruptions = 0
    var isPaused = false
    var hasFinished = false
    var isRunning: Bool { startedAt != nil }
    var remaining: TimeInterval { max(0, Double(targetSeconds) - elapsed) }

    /// Called once when the target rest is reached (play a haptic, etc.).
    @ObservationIgnored var onFinished: (() -> Void)?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var pausedAt: Date?
    @ObservationIgnored private var pausedTotal: TimeInterval = 0

    func start(for exercise: Exercise?, fallback: Int = RestTimer.defaultSeconds) {
        exerciseId = exercise?.id
        targetSeconds = exercise?.defaultRestSeconds ?? fallback
        startedAt = .now
        elapsed = 0
        interruptions = 0
        isPaused = false
        hasFinished = false
        pausedAt = nil
        pausedTotal = 0
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.tick()
            }
        }
    }

    /// Something interrupted the rest (phone call, door). The countdown pauses; the total rest still counts.
    func interrupt() {
        guard isRunning, !isPaused else { return }
        interruptions += 1
        isPaused = true
        pausedAt = .now
    }

    func resume() {
        guard isPaused, let pausedAt else { return }
        pausedTotal += Date.now.timeIntervalSince(pausedAt)
        self.pausedAt = nil
        isPaused = false
    }

    func add(seconds: Int) {
        targetSeconds = max(0, targetSeconds + seconds)
        if remaining > 0 { hasFinished = false }
    }

    /// Stops the timer and returns the actual wall-clock rest and whether it was interrupted.
    @discardableResult
    func stop() -> (seconds: Double, interrupted: Bool)? {
        guard let startedAt else { return nil }
        ticker?.cancel()
        ticker = nil
        let result = (Date.now.timeIntervalSince(startedAt), interruptions > 0)
        self.startedAt = nil
        isPaused = false
        return result
    }

    /// Stamps `restBeforeSeconds`/`restInterrupted` on the set being logged and stops the timer.
    func apply(to entry: inout SetEntry) {
        guard let r = stop() else { return }
        entry.restBeforeSeconds = r.seconds.rounded()
        entry.restInterrupted = r.interrupted
    }

    private func tick() {
        guard let startedAt, !isPaused else { return }
        elapsed = Date.now.timeIntervalSince(startedAt) - pausedTotal
        if !hasFinished && elapsed >= Double(targetSeconds) {
            hasFinished = true
            Haptics.play(.success)
            onFinished?()
        }
    }
}
