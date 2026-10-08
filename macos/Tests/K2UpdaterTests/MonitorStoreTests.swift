import XCTest
@testable import K2Updater

final class MonitorStoreTests: XCTestCase {
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
