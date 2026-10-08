import XCTest
@testable import K2Core

final class MonitorTests: XCTestCase {
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
