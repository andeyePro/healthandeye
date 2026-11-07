import Foundation

/// Accumulates live readings into per-metric, per-source series for a rowing session.
/// Readings from different sources stay in separate series (never silently merged).
public struct SessionRecorder: Sendable {
    public let start: Date
    private var order: [Key] = []
    private var store: [Key: IntervalSeries] = [:]

    private struct Key: Hashable, Sendable {
        let metric: String
        let source: Source
    }

    public init(start: Date) {
        self.start = start
    }

    public mutating func add(metric: String, unit: String, source: Source, value: Double, at time: Date) {
        let key = Key(metric: metric, source: source)
        let sample = Sample(t: time.timeIntervalSince(start), v: value)
        if store[key] == nil {
            order.append(key)
            store[key] = IntervalSeries(metric: metric, unit: unit, source: source, samples: [sample])
        } else {
            store[key]?.samples.append(sample)
        }
    }

    /// Series in the order their first reading arrived.
    public func series() -> [IntervalSeries] {
        order.compactMap { store[$0] }
    }

    /// The first-recorded series for a metric is treated as primary for summaries.
    private func primary(_ metric: String) -> [Sample]? {
        guard let key = order.first(where: { $0.metric == metric }),
              let samples = store[key]?.samples, !samples.isEmpty else { return nil }
        return samples.sorted { $0.t < $1.t }
    }

    /// Keys: distance_m, avg_hr, max_hr, minutes_in_zone, avg_stroke_rate, avg_pace,
    /// energy_kcal_console. A key is omitted when its input series is absent.
    public func summary(zoneSet: ZoneSet?, zoneName: String?) -> [String: Double] {
        var out: [String: Double] = [:]
        if let d = primary("distance_m") { out["distance_m"] = d.map(\.v).max() }
        if let e = primary("energy_kcal") { out["energy_kcal_console"] = e.map(\.v).max() }
        if let s = primary("stroke_rate") { out["avg_stroke_rate"] = mean(s) }
        if let p = primary("pace_s_per_500m") { out["avg_pace"] = mean(p) }
        if let hr = primary("heart_rate") {
            out["avg_hr"] = mean(hr)
            out["max_hr"] = hr.map(\.v).max()
            if let zone = zoneSet?.zones.first(where: { $0.name == zoneName }) {
                out["minutes_in_zone"] = minutesInZone(hr, zone: zone)
            }
        }
        return out
    }

    private func mean(_ samples: [Sample]) -> Double {
        samples.reduce(0) { $0 + $1.v } / Double(samples.count)
    }

    /// Each interval between consecutive readings counts toward the zone of its opening reading.
    private func minutesInZone(_ samples: [Sample], zone: Zone) -> Double {
        var seconds = 0.0
        for (a, b) in zip(samples, samples.dropFirst()) where a.v >= zone.lower && a.v <= zone.upper {
            seconds += b.t - a.t
        }
        return seconds / 60
    }
}
