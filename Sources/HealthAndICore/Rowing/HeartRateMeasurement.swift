import Foundation

/// Heart Rate Measurement (0x2A37).
public struct HeartRateMeasurement: Codable, Equatable, Hashable, Sendable {
    public var bpm: Int
    /// Seconds between beats (wire format is 1/1024 s).
    public var rrIntervals: [Double]
    public var energyExpendedKJ: Int?

    public init(bpm: Int, rrIntervals: [Double] = [], energyExpendedKJ: Int? = nil) {
        self.bpm = bpm
        self.rrIntervals = rrIntervals
        self.energyExpendedKJ = energyExpendedKJ
    }

    public static func parse(_ data: Data) -> HeartRateMeasurement? {
        var r = ByteReader(data)
        guard let flags = r.uint8() else { return nil }
        let bpm: Int
        if flags & 0x01 != 0 {
            guard let v = r.uint16() else { return nil }
            bpm = Int(v)
        } else {
            guard let v = r.uint8() else { return nil }
            bpm = Int(v)
        }
        var out = HeartRateMeasurement(bpm: bpm)
        if flags & 0x08 != 0 {
            guard let v = r.uint16() else { return out }
            out.energyExpendedKJ = Int(v)
        }
        if flags & 0x10 != 0 {
            while let rr = r.uint16() {
                out.rrIntervals.append(Double(rr) / 1024)
            }
        }
        return out
    }
}
