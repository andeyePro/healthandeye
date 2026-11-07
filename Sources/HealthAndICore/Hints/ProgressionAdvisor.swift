import Foundation

public struct Hint: Codable, Equatable, Hashable, Sendable {
    public var exerciseId: String
    /// "too_light", "under_warmed" or "load_dropped".
    public var kind: String
    public var message: String

    public init(exerciseId: String, kind: String, message: String) {
        self.exerciseId = exerciseId
        self.kind = kind
        self.message = message
    }
}

/// Progression hints. Every threshold comes from `Settings.progression`, so the user can tune or disable them.
public enum ProgressionAdvisor {
    public static func hints(for session: Session, history: [Session], catalogue: Catalogue) -> [Hint] {
        let rules = catalogue.settings.progression
        guard rules.enabled else { return [] }
        var out: [Hint] = []
        var exerciseOrder: [String] = []
        for set in session.sets where !exerciseOrder.contains(set.exerciseId) { exerciseOrder.append(set.exerciseId) }

        for exId in exerciseOrder {
            let name = ExportFormat.exerciseName(exId, catalogue)
            let sets = session.sets.filter { $0.exerciseId == exId }

            if let maxReps = catalogue.exercise(id: exId)?.targetRepMax {
                let threshold = maxReps + rules.tooLightRepsAbove
                if let set = sets.first(where: { s in
                    guard let reps = s.reps, let rir = effectiveRIR(s) else { return false }
                    return reps >= threshold && rir >= rules.tooLightRirAtLeast
                }) {
                    out.append(Hint(exerciseId: exId, kind: "too_light",
                                    message: "\(name): \(set.reps!) reps with \(ExportFormat.num(effectiveRIR(set)!, places: 1)) in reserve, target max is \(maxReps). Consider a heavier load."))
                }
            }

            var sides: [Side] = []
            for s in sets where !sides.contains(s.side) { sides.append(s.side) }
            sideLoop: for side in sides {
                let sideSets = sets.filter { $0.side == side }
                for (a, b) in zip(sideSets, sideSets.dropFirst()) {
                    guard let ra = a.reps, let rb = b.reps, rb - ra >= rules.underWarmedRepRise else { continue }
                    // A rise after dropping the load is expected, not a warm-up signal.
                    let ka = ExportFormat.loadKg(a.load, catalogue), kb = ExportFormat.loadKg(b.load, catalogue)
                    if let ka, let kb, kb < ka { continue }
                    let sideText = side == .both ? "" : " (\(side.rawValue))"
                    out.append(Hint(exerciseId: exId, kind: "under_warmed",
                                    message: "\(name)\(sideText): reps rose from \(ra) to \(rb) across sets. The first set may have been under-warmed; consider a warm-up set."))
                    break sideLoop
                }
            }

            if let current = maxLoad(sets, catalogue),
               let previous = history
                .filter({ $0.id != session.id && $0.start < session.start })
                .sorted(by: { $0.start > $1.start })
                .lazy.compactMap({ s in maxLoad(s.sets.filter { $0.exerciseId == exId }, catalogue).map { (s, $0) } })
                .first,
               current < previous.1 - 0.001 {
                let tz = ExportFormat.timeZone(catalogue)
                out.append(Hint(exerciseId: exId, kind: "load_dropped",
                                message: "\(name): top load \(ExportFormat.num(current)) kg, down from \(ExportFormat.num(previous.1)) kg on \(ExportFormat.day(previous.0.start, tz))."))
            }
        }
        return out
    }

    /// RPE 10 = no reps in reserve, so RPE maps to RIR as 10 - RPE when only RPE was logged.
    static func effectiveRIR(_ set: SetEntry) -> Double? {
        set.rir ?? set.rpe.map { 10 - $0 }
    }

    static func maxLoad(_ sets: [SetEntry], _ catalogue: Catalogue) -> Double? {
        sets.compactMap { ExportFormat.loadKg($0.load, catalogue) }.max()
    }
}
