import XCTest
@testable import HealthAndICore

final class RowingParserTests: XCTestCase {
    func testDomyosLikeMinimalPacket() throws {
        let d = try XCTUnwrap(FTMSRowerData.parse(Data([0x00, 0x00, 0x30, 0x2C, 0x01])))
        XCTAssertEqual(d.strokeRate, 24)
        XCTAssertEqual(d.strokeCount, 300)
        XCTAssertEqual(d, FTMSRowerData(strokeRate: 24, strokeCount: 300))
    }

    func testManyFieldsPacket() throws {
        let bytes: [UInt8] = [
            0xAC, 0x0B,             // flags: bits 2,3,5,7,8,9,11
            0x38, 0x64, 0x00,       // stroke rate 28 spm, stroke count 100
            0xD2, 0x04, 0x00,       // distance 1234 m
            0x7D, 0x00,             // pace 125 s/500m
            0x96, 0x00,             // power 150 W
            0x05, 0x00,             // resistance 5
            0x50, 0x00, 0xFF, 0xFF, 0x09, // energy total 80, per hour n/a, per minute 9
            0x8C,                   // HR 140
            0x58, 0x02,             // elapsed 600 s
        ]
        let d = try XCTUnwrap(FTMSRowerData.parse(Data(bytes)))
        XCTAssertEqual(d, FTMSRowerData(
            strokeRate: 28, strokeCount: 100, totalDistanceM: 1234, instantaneousPaceSPer500m: 125,
            instantaneousPowerW: 150, resistanceLevel: 5, totalEnergyKcal: 80, energyPerHour: nil,
            energyPerMinute: 9, heartRate: 140, elapsedSeconds: 600))
    }

    func testRemainingOptionalFieldsWithMoreDataSet() throws {
        let bytes: [UInt8] = [
            0x53, 0x14,             // flags: bits 0,1,4,6,10,12
            0x32,                   // avg stroke rate 25
            0x82, 0x00,             // avg pace 130
            0xFB, 0xFF,             // avg power -5
            0x2D,                   // MET 4.5
            0x2C, 0x01,             // remaining 300 s
        ]
        let d = try XCTUnwrap(FTMSRowerData.parse(Data(bytes)))
        XCTAssertNil(d.strokeRate)
        XCTAssertNil(d.strokeCount)
        XCTAssertEqual(d.averageStrokeRate, 25)
        XCTAssertEqual(d.averagePace, 130)
        XCTAssertEqual(d.averagePowerW, -5)
        XCTAssertEqual(try XCTUnwrap(d.metabolicEquivalent), 4.5, accuracy: 1e-9)
        XCTAssertEqual(d.remainingSeconds, 300)
    }

    func testTruncatedPacketKeepsParsedFields() throws {
        let d = try XCTUnwrap(FTMSRowerData.parse(Data([0xAC, 0x0B, 0x38, 0x64, 0x00, 0xD2, 0x04])))
        XCTAssertEqual(d.strokeRate, 28)
        XCTAssertEqual(d.strokeCount, 100)
        XCTAssertNil(d.totalDistanceM)
        XCTAssertNil(d.instantaneousPaceSPer500m)
        XCTAssertNil(d.heartRate)
    }

    func testSentinelsAndMissingFlags() throws {
        let d = try XCTUnwrap(FTMSRowerData.parse(Data([0x00, 0x00, 0xFF, 0xFF, 0xFF])))
        XCTAssertNil(d.strokeRate)
        XCTAssertNil(d.strokeCount)
        XCTAssertNil(FTMSRowerData.parse(Data([0x00])))
        XCTAssertNil(FTMSRowerData.parse(Data()))
    }

    func testFeatureParse() throws {
        let f = try XCTUnwrap(FTMSFeature.parse(Data([0xA6, 0x46, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00])))
        XCTAssertEqual(f.fitnessMachineFeatures, 0x46A6)
        XCTAssertTrue(f.supportsCadence)
        XCTAssertTrue(f.supportsTotalDistance)
        XCTAssertTrue(f.supportsPace)
        XCTAssertTrue(f.supportsResistanceLevel)
        XCTAssertTrue(f.supportsExpendedEnergy)
        XCTAssertTrue(f.supportsHeartRate)
        XCTAssertTrue(f.supportsPower)
        XCTAssertTrue(f.supportsResistanceTarget)
        XCTAssertFalse(f.supportsPowerTarget)
        XCTAssertFalse(f.supportsHeartRateTarget)

        let none = try XCTUnwrap(FTMSFeature.parse(Data([0x00, 0x00, 0x00, 0x00, 0x18, 0x00, 0x00, 0x00])))
        XCTAssertFalse(none.supportsCadence)
        XCTAssertTrue(none.supportsPowerTarget)
        XCTAssertTrue(none.supportsHeartRateTarget)
        XCTAssertNil(FTMSFeature.parse(Data([0x01, 0x02])))
    }

    func testControlPointEncodings() {
        XCTAssertEqual(FTMSControlPoint.requestControl(), Data([0x00]))
        XCTAssertEqual(FTMSControlPoint.reset(), Data([0x01]))
        XCTAssertEqual(FTMSControlPoint.setResistanceLevel(5.5), Data([0x04, 55]))
        XCTAssertEqual(FTMSControlPoint.setResistanceLevel(-1), Data([0x04, 0]))
        XCTAssertEqual(FTMSControlPoint.setResistanceLevel(100), Data([0x04, 255]))
        XCTAssertEqual(FTMSControlPoint.setTargetPower(300), Data([0x05, 0x2C, 0x01]))
        XCTAssertEqual(FTMSControlPoint.start(), Data([0x07]))
        XCTAssertEqual(FTMSControlPoint.stop(), Data([0x08, 0x01]))
        XCTAssertEqual(FTMSControlPoint.pause(), Data([0x08, 0x02]))
    }

    func testControlPointResponse() throws {
        let r = try XCTUnwrap(FTMSControlPoint.parseResponse(Data([0x80, 0x04, 0x01])))
        XCTAssertEqual(r.op, 0x04)
        XCTAssertEqual(r.result, 0x01)
        let typed = try XCTUnwrap(FTMSControlPoint.parseResult(Data([0x80, 0x00, 0x05])))
        XCTAssertEqual(typed.op, 0x00)
        XCTAssertEqual(typed.result, .controlNotPermitted)
        XCTAssertEqual(FTMSControlPoint.ResultCode(rawValue: 0x02), .notSupported)
        XCTAssertEqual(FTMSControlPoint.ResultCode(rawValue: 0x03), .invalidParameter)
        XCTAssertEqual(FTMSControlPoint.ResultCode(rawValue: 0x04), .failed)
        XCTAssertNil(FTMSControlPoint.parseResponse(Data([0x04, 0x04, 0x01])))
        XCTAssertNil(FTMSControlPoint.parseResponse(Data([0x80, 0x04])))
    }

    func testHeartRateMeasurement() throws {
        XCTAssertEqual(HeartRateMeasurement.parse(Data([0x00, 72])), HeartRateMeasurement(bpm: 72))
        XCTAssertEqual(HeartRateMeasurement.parse(Data([0x01, 0x2C, 0x01]))?.bpm, 300)
        let full = try XCTUnwrap(HeartRateMeasurement.parse(Data([0x18, 0x50, 0x48, 0x00, 0x00, 0x04, 0x00, 0x02])))
        XCTAssertEqual(full.bpm, 80)
        XCTAssertEqual(full.energyExpendedKJ, 72)
        XCTAssertEqual(full.rrIntervals, [1.0, 0.5])
        XCTAssertNil(HeartRateMeasurement.parse(Data([0x01, 0x2C])))
        XCTAssertNil(HeartRateMeasurement.parse(Data()))
    }

    func testUUIDs() {
        XCTAssertEqual(FTMSUUID.service, "1826")
        XCTAssertEqual(FTMSUUID.rowerData, "2AD1")
        XCTAssertEqual(FTMSUUID.controlPoint, "2AD9")
        XCTAssertEqual(FTMSUUID.hrMeasurement, "2A37")
    }
}
