#if os(watchOS)
import Foundation
import Observation
@preconcurrency import HealthKit
import HealthAndICore

/// Watch-side live workout. Keeps the app running during a session and streams HR from the
/// Watch sensor or a strap (e.g. Polar H10) paired in Watch Settings.
@Observable @MainActor
final class WorkoutSessionController: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = WorkoutSessionController()

    var heartRate: Int?
    var activeEnergyKcal: Double?
    var isRunning = false
    var startDate: Date?
    var hrSamples: [(Date, Int)] = []
    var lastError: String?

    @ObservationIgnored var onHeartRate: ((Int, Date) -> Void)?
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?

    private var store: HKHealthStore { HealthKitService.shared.store }

    func start(activity: HKWorkoutActivityType) async {
        guard session == nil else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = activity
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            hrSamples = []
            heartRate = nil
            let now = Date.now
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            startDate = now
            isRunning = true
        } catch {
            lastError = error.localizedDescription
            session = nil
            builder = nil
        }
    }

    /// Ends the session. When `save` is true the workout is written to Health and its UUID returned.
    func stop(save: Bool) async -> String? {
        guard let session, let builder else { return nil }
        session.end()
        isRunning = false
        defer { self.session = nil; self.builder = nil }
        do {
            try await builder.endCollection(at: .now)
            if save {
                return try await builder.finishWorkout()?.uuid.uuidString
            }
            builder.discardWorkout()
        } catch {
            lastError = error.localizedDescription
        }
        return nil
    }

    // MARK: Delegates (called on HealthKit's queues)

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        let running = toState == .running
        Task { @MainActor in self.isRunning = running }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let msg = error.localizedDescription
        Task { @MainActor in self.lastError = msg }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hrType = HKQuantityType(.heartRate)
        let energyType = HKQuantityType(.activeEnergyBurned)
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let bpm = collectedTypes.contains(hrType)
            ? workoutBuilder.statistics(for: hrType)?.mostRecentQuantity()?.doubleValue(for: bpmUnit) : nil
        let kcal = collectedTypes.contains(energyType)
            ? workoutBuilder.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) : nil
        Task { @MainActor in
            if let bpm {
                let value = Int(bpm.rounded())
                let now = Date.now
                self.heartRate = value
                self.hrSamples.append((now, value))
                self.onHeartRate?(value, now)
            }
            if let kcal { self.activeEnergyKcal = kcal }
        }
    }
}
#endif
