import XCTest
import Combine
import K2Core
@testable import K2Updater

final class MonitorStoreTests: XCTestCase {
    private func status(time: Double, recording: Bool = true, paused: Bool = false,
                        stale: Bool = false) throws -> MonitorStatus {
        let data = Data("""
        {"recording":\(recording),"paused":\(paused),"stale":\(stale),
         "record_count":\(Int(time * 100)),"elapsed":\(time),
         "latest":{"time":\(time),"voltage":5,"current":-2,"power":10,"signed_power":-10,"segment":0}}
        """.utf8)
        return try WireCodec.decoder.decode(MonitorStatus.self, from: data)
    }

    @MainActor func testTelemetryDoesNotInvalidateWindowButKeepsEveryDisplayUpdate() throws {
        let store = MonitorStore()
        store.applyStatus(try status(time: 0))
        var windowUpdates = 0, readingUpdates = 0
        let windowToken = store.objectWillChange.sink { windowUpdates += 1 }
        let readingToken = store.telemetry.$latest.dropFirst().sink { _ in readingUpdates += 1 }
        for step in 1...100 { store.applyStatus(try status(time: Double(step) / 10)) }
        XCTAssertEqual(windowUpdates, 0)
        XCTAssertEqual(readingUpdates, 100)
        XCTAssertEqual(store.latest?.time, 10)
        XCTAssertEqual(store.state?.recordCount, 1000)
        withExtendedLifetime((windowToken, readingToken)) {}
    }

    @MainActor func testRecordingPauseAndStaleTransitionsStillInvalidateControls() throws {
        let store = MonitorStore()
        store.applyStatus(try status(time: 0))
        var updates = 0
        let token = store.objectWillChange.sink { updates += 1 }
        store.applyStatus(try status(time: 1, paused: true))
        XCTAssertTrue(store.paused)
        XCTAssertGreaterThan(updates, 0)
        updates = 0
        store.applyStatus(try status(time: 2, paused: true, stale: true))
        XCTAssertEqual(store.state?.stale, true)
        XCTAssertGreaterThan(updates, 0)
        updates = 0
        store.applyStatus(try status(time: 3, recording: false))
        XCTAssertFalse(store.recording)
        XCTAssertFalse(store.paused)
        XCTAssertGreaterThan(updates, 0)
        withExtendedLifetime(token) {}
    }

    @MainActor func testInvalidSelectionCannotReachChartDomain() {
        let store = MonitorStore()
        store.select(.nan, 1)
        XCTAssertFalse(store.selectedRange)
        XCTAssertNotNil(store.errorMessage)
    }
    @MainActor func testDeviceMaintenanceBlockedDuringCapture() {
        let store = UpdaterStore()
        store.monitorConnected = true
        store.dfuConfirmed = true
        store.probe()
        XCTAssertFalse(store.isBusy)
        XCTAssertFalse(store.canProbe)
        XCTAssertFalse(store.canUseResources)
        XCTAssertTrue(store.errorMessage?.contains("断开采集") == true)
    }
}
