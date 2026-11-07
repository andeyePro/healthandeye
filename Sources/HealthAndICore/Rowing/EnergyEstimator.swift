import Foundation

/// HR-derived energy expenditure, Keytel et al. 2005 (J Sports Sci 23:289), without VO2max.
public enum EnergyEstimator {
    /// kcal/min for one HR reading, floored at 0; nil when sex is neither male nor female
    /// (Keytel publishes only sex-specific equations).
    public static func kcalPerMinute(hr: Double, sex: Sex, massKg: Double, age: Double) -> Double? {
        let kj: Double
        switch sex {
        case .male: kj = -55.0969 + 0.6309 * hr + 0.1988 * massKg + 0.2017 * age
        case .female: kj = -20.4022 + 0.4472 * hr - 0.1263 * massKg + 0.074 * age
        default: return nil
        }
        return Swift.max(0, kj / 4.184)
    }

    /// Trapezoidal integral of kcal/min over the series. Nil if sex, mass or age is missing
    /// or the series has fewer than two samples.
    public static func kcal(hrSeries: IntervalSeries, profile: Profile, on date: Date = Date()) -> Double? {
        guard let sex = profile.sex, let mass = profile.bodyMassKg, let dob = profile.dateOfBirth else { return nil }
        let age = date.timeIntervalSince(dob) / (365.2425 * 86_400)
        guard age > 0 else { return nil }
        let samples = hrSeries.samples.sorted { $0.t < $1.t }
        guard samples.count >= 2 else { return nil }
        var total = 0.0
        for (a, b) in zip(samples, samples.dropFirst()) {
            guard let ra = kcalPerMinute(hr: a.v, sex: sex, massKg: mass, age: age),
                  let rb = kcalPerMinute(hr: b.v, sex: sex, massKg: mass, age: age) else { return nil }
            total += (ra + rb) / 2 * (b.t - a.t) / 60
        }
        return total
    }
}
