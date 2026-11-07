import Foundation
import HealthKit
import HealthAndICore

/// Writes a finished session to Apple Health when the write module is on, then records the
/// workout id on the session so the export shows the link.
@MainActor
enum HealthPush {
    static func workout(_ session: Session, activity: HKWorkoutActivityType) {
        let store = StoreController.shared
        guard store.isOn(.healthKitWrite) else { return }
        let energy = session.summary["energy_kcal_hr"] ?? (store.catalogue.settings.energyPrefersHR ? nil : session.summary["energy_kcal_console"])
        let hr: [(Date, Int)] = session.intervals
            .first { $0.metric == "heart_rate" }?
            .samples.map { (session.start.addingTimeInterval($0.t), Int($0.v)) } ?? []
        Task {
            do {
                if let id = try await HealthKitService.shared.saveWorkout(
                    session: session, activity: activity, energyKcal: energy,
                    distanceM: session.summary["distance_m"], hrSamples: hr) {
                    var updated = session
                    updated.healthKitWorkoutId = id
                    store.saveSession(updated)
                }
            } catch {
                store.lastError = "Could not save to Apple Health: \(error.localizedDescription)"
            }
        }
    }
}
