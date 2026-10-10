import XCTest
import K2Core
@testable import K2Updater

final class MonitorChartTests: XCTestCase {
    func testVectorizedProjectionPreservesEveryValueAndSegment() throws {
        let points = try Self.samples()
        for channel in MonitorChannel.allCases {
            let projected = MonitorLinePoint.project(points, channel: channel)
            let expected = points.compactMap { point in
                point.value(channel).map { MonitorLinePoint(time: point.time, value: $0, segment: point.segment) }
            }
            XCTAssertEqual(projected, expected)
        }
        let current = MonitorLinePoint.project(points, channel: .current)
        XCTAssertEqual(current.count, 1200)
        XCTAssertEqual(current[600].value, -12) // narrow negative spike
        XCTAssertEqual(current[599].segment, 0)
        XCTAssertEqual(current[600].segment, 1) // no line across the acquisition gap
        let temperature = MonitorLinePoint.project(points, channel: .tempOut)
        XCTAssertEqual(temperature.count, 600)
        XCTAssertEqual(temperature.first?.time, points[1].time)
    }

    static func samples() throws -> [MonitorSample] {
        try (0..<1200).map { index in
            let time = Double(index) / 10 + (index >= 600 ? 5 : 0)
            let current = index == 600 ? -12.0 : -0.2 + sin(Double(index) / 20) * 0.05
            return try WireCodec.decoder.decode(MonitorSample.self, from: Data("""
            {"time":\(time),"voltage":5.06,"current":\(current),"power":\(abs(current)*5.06),
             "signed_power":\(current*5.06),"segment":\(index >= 600 ? 1 : 0),
             "temp_in":27,"temp_out":\(index % 2 == 0 ? "null" : "26"),"dp":0.6,"dn":0.5}
            """.utf8))
        }
    }
}
