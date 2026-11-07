import Foundation
@preconcurrency import HealthKit
import HealthAndICore

/// Apple Health access. Permissions are requested per module toggle; writes always create new
/// samples (HealthKit never lets us overwrite another app's data, and we never delete).
@MainActor
final class HealthKitService {
    static let shared = HealthKitService()

    let store = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private static let requestedReadKey = "healthkit_requested_read"
    /// Identifiers we have asked to read. HealthKit hides read authorisation, so this is the gate.
    private(set) var requestedRead: Set<String> = Set(UserDefaults.standard.stringArray(forKey: requestedReadKey) ?? [])

    /// Daily metrics read when `health_kit_read` is on: metric key -> quantity type and unit.
    static let dailyMetrics: [(key: String, id: HKQuantityTypeIdentifier, unit: HKUnit, cumulative: Bool)] = [
        ("resting_hr", .restingHeartRate, HKUnit.count().unitDivided(by: .minute()), false),
        ("hrv_sdnn_ms", .heartRateVariabilitySDNN, .secondUnit(with: .milli), false),
        ("vo2_max", .vo2Max, HKUnit(from: "ml/kg*min"), false),
        ("weight_kg", .bodyMass, .gramUnit(with: .kilo), false),
        ("body_fat_pct", .bodyFatPercentage, .percent(), false),
        ("steps", .stepCount, .count(), true),
        ("active_energy_kcal", .activeEnergyBurned, .kilocalorie(), true),
    ]

    static var defaultReadTypes: Set<HKObjectType> {
        var set: Set<HKObjectType> = Set(dailyMetrics.map { HKQuantityType($0.id) })
        set.insert(HKQuantityType(.heartRate))
        set.insert(HKQuantityType(.leanBodyMass))
        set.insert(HKQuantityType(.waistCircumference))
        set.insert(HKCategoryType(.sleepAnalysis))
        set.insert(HKObjectType.workoutType())
        return set
    }

    static var defaultWriteTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
         HKQuantityType(.distanceRowing)]
    }

    /// Request only what the given types list; callers pass empty sets for switched-off modules.
    @discardableResult
    func request(read: Set<HKObjectType>, write: Set<HKSampleType>) async -> Bool {
        guard isAvailable, !(read.isEmpty && write.isEmpty) else { return false }
        do {
            try await store.requestAuthorization(toShare: write, read: read)
            requestedRead.formUnion(read.map(\.identifier))
            UserDefaults.standard.set(Array(requestedRead), forKey: Self.requestedReadKey)
            return true
        } catch {
            return false
        }
    }

    /// Request permissions for the HealthKit modules currently switched on.
    @discardableResult
    func requestForEnabledModules(_ controller: StoreController = .shared) async -> Bool {
        let read = controller.isOn(.healthKitRead) ? Self.defaultReadTypes : []
        let write = controller.isOn(.healthKitWrite) ? Self.defaultWriteTypes : []
        return await request(read: read, write: write)
    }

    func canWrite(_ type: HKObjectType) -> Bool {
        store.authorizationStatus(for: type) == .sharingAuthorized
    }

    // MARK: Write

    /// Saves a new workout with optional energy, distance and HR samples. Returns the workout UUID.
    func saveWorkout(session: Session, activity: HKWorkoutActivityType, energyKcal: Double?,
                     distanceM: Double?, hrSamples: [(Date, Int)]) async throws -> String? {
        guard isAvailable, canWrite(HKObjectType.workoutType()) else { return nil }
        let config = HKWorkoutConfiguration()
        config.activityType = activity
        config.locationType = .indoor
        let start = session.start
        let end = session.end ?? .now
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        try await builder.beginCollection(at: start)

        var samples: [HKSample] = []
        if let energyKcal, energyKcal > 0, canWrite(HKQuantityType(.activeEnergyBurned)) {
            samples.append(HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energyKcal),
                                            start: start, end: end))
        }
        if let distanceM, distanceM > 0, activity == .rowing, canWrite(HKQuantityType(.distanceRowing)) {
            samples.append(HKQuantitySample(type: HKQuantityType(.distanceRowing),
                                            quantity: HKQuantity(unit: .meter(), doubleValue: distanceM),
                                            start: start, end: end))
        }
        if !hrSamples.isEmpty, canWrite(HKQuantityType(.heartRate)) {
            let unit = HKUnit.count().unitDivided(by: .minute())
            for (date, bpm) in hrSamples where date >= start && date <= end {
                samples.append(HKQuantitySample(type: HKQuantityType(.heartRate),
                                                quantity: HKQuantity(unit: unit, doubleValue: Double(bpm)),
                                                start: date, end: date))
            }
        }
        if !samples.isEmpty { try await builder.addSamples(samples) }
        try await builder.addMetadata([HKMetadataKeyExternalUUID: session.id])
        try await builder.endCollection(at: end)
        let workout = try await builder.finishWorkout()
        return workout?.uuid.uuidString
    }

    // MARK: Read

    /// Metrics for the calendar day containing `date`, keyed as in the daily JSON. Only types we
    /// were granted are queried; missing data is simply absent.
    func readDailyMetrics(for date: Date) async -> [String: Double] {
        guard isAvailable else { return [:] }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [:] }
        let range = HKQuery.predicateForSamples(withStart: dayStart, end: dayEnd)
        var out: [String: Double] = [:]

        for metric in Self.dailyMetrics {
            let type = HKQuantityType(metric.id)
            guard requestedRead.contains(type.identifier) else { continue }
            if metric.cumulative {
                let d = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: type, predicate: range), options: .cumulativeSum)
                if let q = try? await d.result(for: store)?.sumQuantity() {
                    out[metric.key] = q.doubleValue(for: metric.unit)
                }
            } else {
                // Latest value on or before the end of the day (weight etc. are not logged daily).
                let upTo = HKQuery.predicateForSamples(withStart: nil, end: dayEnd)
                let d = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: upTo)],
                                                sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1)
                if let s = try? await d.result(for: store).first {
                    var v = s.quantity.doubleValue(for: metric.unit)
                    if metric.id == .bodyFatPercentage { v *= 100 }
                    out[metric.key] = v
                }
            }
        }

        let sleepType = HKCategoryType(.sleepAnalysis)
        if requestedRead.contains(sleepType.identifier) {
            // Sleep ending on this day (the night before counts towards today).
            let sleepRange = HKQuery.predicateForSamples(withStart: dayStart.addingTimeInterval(-12 * 3600), end: dayEnd)
            let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
            let d = HKSampleQueryDescriptor(predicates: [.categorySample(type: sleepType, predicate: sleepRange)],
                                            sortDescriptors: [])
            if let samples = try? await d.result(for: store) {
                let seconds = samples
                    .filter { asleep.contains($0.value) && $0.endDate > dayStart && $0.endDate <= dayEnd }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                if seconds > 0 { out["sleep_minutes"] = seconds / 60 }
            }
        }
        return out
    }
}
