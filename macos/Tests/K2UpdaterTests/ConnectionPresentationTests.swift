import XCTest
@testable import K2Updater

final class ConnectionPresentationTests: XCTestCase {
    func testCaptureStartupDoesNotClaimLiveData() {
        XCTAssertEqual(ConnectionPresentation.capture(connected: true, disconnecting: false,
            hasSample: false, stale: false, recording: false, paused: false), .waiting)
        XCTAssertEqual(ConnectionPresentation.capture(connected: true, disconnecting: false,
            hasSample: true, stale: false, recording: false, paused: false), .live)
        XCTAssertNil(ConnectionPresentation.capture(connected: false, disconnecting: false,
            hasSample: true, stale: false, recording: true, paused: false))
    }

    func testStaleAndDisconnectingOverrideRecordingBadge() {
        XCTAssertEqual(ConnectionPresentation.capture(connected: true, disconnecting: false,
            hasSample: true, stale: true, recording: true, paused: false), .stale)
        XCTAssertEqual(ConnectionPresentation.capture(connected: true, disconnecting: true,
            hasSample: true, stale: true, recording: true, paused: false), .disconnecting)
        XCTAssertEqual(ConnectionPresentation.capture(connected: true, disconnecting: false,
            hasSample: true, stale: false, recording: true, paused: true), .paused)
    }

    @MainActor func testDFUDeclarationRequiresIdentityAndSelectedInterface() {
        let updater = UpdaterStore()
        let monitor = MonitorStore()
        updater.devices = [DeviceInfo(pathHex: "test-interface", productString: "K2",
            manufacturerString: nil, serialNumber: nil, interfaceNumber: 0)]
        updater.selectedPath = "test-interface"
        XCTAssertEqual(ConnectionPresentation.current(updater: updater, monitor: monitor), .available)
        updater.dfuConfirmed = true
        XCTAssertEqual(ConnectionPresentation.current(updater: updater, monitor: monitor), .dfuDeclared)
        updater.identity = IdentityInfo(bootStrings: [], infoSha256: "", confirmedK2: true,
            currentVersion: "5.8", currentMarkerHex: nil)
        XCTAssertEqual(ConnectionPresentation.current(updater: updater, monitor: monitor), .dfuReady)
        updater.selectedPath = ""
        XCTAssertEqual(ConnectionPresentation.current(updater: updater, monitor: monitor), .unavailable)
        // Presentation never clears the real identity or changes DFU preparation.
        XCTAssertEqual(updater.identity?.currentVersion, "5.8")
        XCTAssertTrue(updater.dfuConfirmed)
        XCTAssertFalse(updater.isBusy)
    }
}
