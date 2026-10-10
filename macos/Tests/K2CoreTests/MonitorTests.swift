import XCTest
@testable import K2Core

final class MonitorTests: XCTestCase {
    func testBinaryCursorLookupMatchesLinearLookupIncludingDuplicatesAndTies() throws {
        let times = [0.0, 1, 1, 2, 4, 8]
        let points = try times.enumerated().map { index, time in
            try WireCodec.decoder.decode(MonitorSample.self, from: Data("""
            {"time":\(time),"voltage":\(index),"current":-2,"power":10,"signed_power":-10,"segment":0}
            """.utf8))
        }
        for time in stride(from: -1.0, through: 10, by: 0.125) {
            let expected = points.min { abs($0.time - time) < abs($1.time - time) }
            let actual = MonitorSample.nearest(in: points, to: time)
            XCTAssertEqual(actual?.voltage, expected?.voltage, "cursor at \(time)")
        }
        XCTAssertNil(MonitorSample.nearest(in: [], to: 0))
        XCTAssertNil(MonitorSample.nearest(in: points, to: .nan))
        XCTAssertNil(MonitorSample.nearest(in: points, to: .infinity))
    }

    func testSignedSampleAndMissingTemperatureDecode() throws {
        let data = Data(#"{"time":1.5,"voltage":5,"current":-2,"power":10,"signed_power":-10,"segment":3}"#.utf8)
        let sample = try WireCodec.decoder.decode(MonitorSample.self, from: data)
        XCTAssertEqual(sample.current, -2)
        XCTAssertEqual(sample.signedPower, -10)
        XCTAssertNil(sample.tempOut)
        XCTAssertEqual(sample.value(.current), -2)
    }
    func testCrossDayDisplayAndInvalidNumbers() {
        XCTAssertEqual(MonitorFormat.elapsed(86401.234), "1.00:00:01.234")
        XCTAssertEqual(MonitorFormat.number(.nan), "—")
        XCTAssertEqual(MonitorFormat.elapsed(-1), "—")
    }
    func testMonitorRequestDoesNotRequireDFU() throws {
        var request = BackendRequest(operation: .monitor, dataDirectory: "/tmp")
        request.devicePathHex = "01"
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: WireCodec.requestData(request)) as? [String: Any])
        XCTAssertEqual(object["operation"] as? String, "monitor")
        XCTAssertEqual(object["dfu_confirmed"] as? Bool, false)
        XCTAssertFalse(BackendOperation.monitor.isWrite)
    }
}
