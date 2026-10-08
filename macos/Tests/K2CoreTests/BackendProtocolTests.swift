import XCTest
@testable import K2Core

final class BackendProtocolTests: XCTestCase {
    func testSplitUTF8AndMultipleEvents() throws {
        let text = "{\"schema\":1,\"id\":\"job\",\"operation\":\"probe\",\"event\":\"progress\",\"stage\":\"identify\",\"message\":\"读取设备\"}\n{\"schema\":1,\"id\":\"job\",\"operation\":\"probe\",\"event\":\"result\",\"value\":{\"identity\":{\"current_version\":\"3.4\"}}}\n"
        let data = Data(text.utf8), decoder = EventLineDecoder()
        var result: [BackendEvent] = []
        for byte in data { result += try decoder.feed(Data([byte])) }
        try decoder.finish()
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].message, "读取设备")
        XCTAssertEqual(result[1].value?["identity"]?["current_version"]?.string, "3.4")
    }

    func testIncompleteAndWrongVersionRejected() throws {
        let decoder = EventLineDecoder()
        _ = try decoder.feed(Data("{\"schema\":1".utf8))
        XCTAssertThrowsError(try decoder.finish())
        let wrong = Data("{\"schema\":2,\"id\":\"job\",\"operation\":\"probe\",\"event\":\"ready\"}\n".utf8)
        XCTAssertThrowsError(try EventLineDecoder().feed(wrong))
    }

    func testRequestCarriesExplicitWriteConfirmation() throws {
        var request = BackendRequest(operation: .upgrade, dataDirectory: "/local/data")
        request.firmwareSha256 = "hash"; request.dfuConfirmed = true; request.confirmed = true
        let object = try JSONSerialization.jsonObject(with: WireCodec.requestData(request)) as! [String: Any]
        XCTAssertEqual(object["firmware_sha256"] as? String, "hash")
        XCTAssertEqual(object["confirmed"] as? Bool, true)
        XCTAssertEqual(object["dfu_confirmed"] as? Bool, true)
        XCTAssertEqual(object["simulation"] as? Bool, false)
        XCTAssertFalse(BackendOperation.upgrade.canCancel)
        XCTAssertTrue(BackendOperation.backup.canCancel)
    }
}
