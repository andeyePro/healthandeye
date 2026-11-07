import Foundation

public enum LoadBuilder {
    /// Sum of parts plus `fixedKg`. Nil when the load is empty or any part's equipment or mass is unknown.
    public static func totalKg(_ load: Load, catalogue: Catalogue) -> Double? {
        if load.parts.isEmpty && load.fixedKg == nil { return nil }
        var total = load.fixedKg ?? 0
        for part in load.parts {
            guard let mass = catalogue.equipment(id: part.equipmentId)?.massKg else { return nil }
            total += mass * Double(part.count)
        }
        return total
    }

    /// One row per part (unknown equipment shows its id and 0 kg), then a "fixed" row if `fixedKg` is set.
    public static func breakdown(_ load: Load, catalogue: Catalogue) -> [(name: String, count: Int, kg: Double)] {
        var rows: [(name: String, count: Int, kg: Double)] = load.parts.map { part in
            let eq = catalogue.equipment(id: part.equipmentId)
            return (eq?.name ?? part.equipmentId, part.count, (eq?.massKg ?? 0) * Double(part.count))
        }
        if let fixed = load.fixedKg { rows.append(("fixed", 1, fixed)) }
        return rows
    }

    /// Human-readable warnings for equipment limits the load exceeds. Checks, on the exercise's and load's
    /// equipment: `dumbbell_max_kg` and `max_kg` against the total, and `per_sleeve_max` (on plates)
    /// against the plate count spread over the bar sleeves in the load.
    public static func limitWarnings(load: Load, exercise: Exercise?, catalogue: Catalogue) -> [String] {
        var ids: [String] = exercise?.equipmentIds ?? []
        for part in load.parts where !ids.contains(part.equipmentId) { ids.append(part.equipmentId) }
        let items = ids.compactMap { catalogue.equipment(id: $0) }
        let total = totalKg(load, catalogue: catalogue)
        var warnings: [String] = []

        if let total {
            for eq in items {
                if let max = eq.limits["dumbbell_max_kg"], total > max {
                    warnings.append("\(eq.name): dumbbell limit \(fmt(max)) kg exceeded (\(fmt(total)) kg)")
                }
                if let max = eq.limits["max_kg"], total > max {
                    warnings.append("\(eq.name): limit \(fmt(max)) kg exceeded (\(fmt(total)) kg)")
                }
            }
        }

        let partEquipment = load.parts.compactMap { part in catalogue.equipment(id: part.equipmentId).map { ($0, part.count) } }
        let bars = partEquipment.filter { $0.0.kind == "bar" }.reduce(0) { $0 + $1.1 }
        let sleeves = max(bars, 1) * 2
        let plates = partEquipment.filter { $0.0.kind == "plate" }.reduce(0) { $0 + $1.1 }
        for (eq, _) in partEquipment where eq.kind == "plate" {
            if let perSleeve = eq.limits["per_sleeve_max"], Double(plates) > perSleeve * Double(sleeves) {
                warnings.append("\(eq.name): at most \(fmt(perSleeve)) per sleeve, load has \(plates) plates on \(sleeves) sleeves")
            }
        }
        return warnings
    }

    static func fmt(_ v: Double) -> String {
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
