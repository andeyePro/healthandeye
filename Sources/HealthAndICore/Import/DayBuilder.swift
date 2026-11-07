import Foundation

/// Builds a day snapshot: intake totals from the food library, plus progress against daily targets.
public enum DayBuilder {
    public static func build(date: String, intake: [Intake], foods: [Food], metrics: [String: Double],
                             targets: [Target]) -> DaySnapshot {
        var totals: [String: Double] = [:]
        for item in intake {
            guard let food = foods.first(where: { $0.id == item.foodId }) else { continue }
            for (nutrient, per100) in food.per100g {
                totals[nutrient, default: 0] += per100 * item.grams / 100
            }
        }
        let progress = targets.filter { $0.enabled && $0.period == .day }.map { t -> TargetProgress in
            let value = totals[t.metric] ?? metrics[t.metric] ?? 0
            return TargetProgress(targetId: t.id, value: value, target: t.value, met: value >= t.value)
        }
        return DaySnapshot(date: date, metrics: metrics, intake: intake, totals: totals, targets: progress)
    }
}
