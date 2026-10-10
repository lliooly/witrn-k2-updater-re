import XCTest
@testable import K2Updater

final class FirmwareLogTailTests: XCTestCase {
    @MainActor func testPartialUTF8RecordsAreCompletedAndErrorsRemainVisible() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let data = Data("{\"time\":\"2026-10-10T13:00:00.123456+00:00\",\"kind\":\"error\",\"message\":\"设备断开\"}\n".utf8)
        let split = data.count - 5
        try data.prefix(split).write(to: path)
        let tail = FirmwareLogTail()
        tail.read(path: path.path)
        XCTAssertTrue(tail.lines.isEmpty)
        let file = try FileHandle(forWritingTo: path)
        try file.seekToEnd(); try file.write(contentsOf: data.suffix(data.count - split)); try file.close()
        tail.read(path: path.path)
        XCTAssertEqual(tail.lines.count, 1)
        XCTAssertTrue(tail.lines[0].isError)
        XCTAssertTrue(tail.lines[0].text.contains("设备断开"))
        XCTAssertTrue(tail.lines[0].text.contains("13:00:00.123"))
        tail.read(path: path.path)
        XCTAssertEqual(tail.lines.count, 1)
    }

    @MainActor func testLargeTracesKeepLatestRecordsAndHandleTruncation() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let records = (0..<5000).map { "{\"kind\":\"rx\",\"sequence\":\($0),\"hex\":\"\(String(repeating: "ab", count: 64))\"}\n" }.joined()
        try Data(records.utf8).write(to: path)
        let tail = FirmwareLogTail()
        tail.read(path: path.path)
        XCTAssertEqual(tail.lines.count, 300)
        XCTAssertTrue(tail.lines.last?.text.contains("4999") == true)
        try Data("{\"kind\":\"start\",\"command\":\"backup\"}\n".utf8).write(to: path)
        tail.read(path: path.path)
        XCTAssertEqual(tail.lines.count, 1)
        XCTAssertTrue(tail.lines[0].text.contains("START"))
    }
}
