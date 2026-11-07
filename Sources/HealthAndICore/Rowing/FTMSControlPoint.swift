import Foundation

/// FTMS Control Point (0x2AD9) request encodings and response indication parsing.
public enum FTMSControlPoint {
    public enum OpCode: UInt8, Sendable {
        case requestControl = 0x00
        case reset = 0x01
        case setResistanceLevel = 0x04
        case setTargetPower = 0x05
        case start = 0x07
        case stop = 0x08
        case response = 0x80
    }

    public enum ResultCode: UInt8, Sendable {
        case success = 0x01
        case notSupported = 0x02
        case invalidParameter = 0x03
        case failed = 0x04
        case controlNotPermitted = 0x05
    }

    public static func requestControl() -> Data { Data([OpCode.requestControl.rawValue]) }

    public static func reset() -> Data { Data([OpCode.reset.rawValue]) }

    /// Level in machine units; encoded as uint8 at 0.1 resolution, clamped to 0...25.5.
    public static func setResistanceLevel(_ level: Double) -> Data {
        let tenths = (level * 10).rounded()
        let clamped = UInt8(max(0, min(255, tenths)))
        return Data([OpCode.setResistanceLevel.rawValue, clamped])
    }

    public static func setTargetPower(_ watts: Int) -> Data {
        var data = Data([OpCode.setTargetPower.rawValue])
        let clamped = Int16(max(Int(Int16.min), min(Int(Int16.max), watts)))
        data.appendLE(UInt16(bitPattern: clamped))
        return data
    }

    public static func start() -> Data { Data([OpCode.start.rawValue]) }

    public static func stop() -> Data { Data([OpCode.stop.rawValue, 0x01]) }

    public static func pause() -> Data { Data([OpCode.stop.rawValue, 0x02]) }

    /// Parses a response indication `0x80 [request op] [result]`.
    public static func parseResponse(_ data: Data) -> (op: UInt8, result: UInt8)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 3, bytes[0] == OpCode.response.rawValue else { return nil }
        return (op: bytes[1], result: bytes[2])
    }

    /// Typed form of `parseResponse`; nil for a malformed packet or an unknown result code.
    public static func parseResult(_ data: Data) -> (op: UInt8, result: ResultCode)? {
        guard let raw = parseResponse(data), let result = ResultCode(rawValue: raw.result) else { return nil }
        return (op: raw.op, result: result)
    }
}
