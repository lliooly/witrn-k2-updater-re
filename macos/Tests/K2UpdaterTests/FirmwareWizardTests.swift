import XCTest
@testable import K2Updater

final class FirmwareWizardTests: XCTestCase {
    @MainActor func testPlugAndUnplugSelectsDeviceAndInvalidatesDFU() {
        let store = selectedStore(confirmed: true)
        let device = store.devices[0]
        store.applyDeviceList([])
        XCTAssertTrue(store.devices.isEmpty)
        XCTAssertEqual(store.selectedPath, "")
        XCTAssertNil(store.identity)
        XCTAssertFalse(store.dfuConfirmed)
        XCTAssertFalse(store.canUseResources)
        store.applyDeviceList([device])
        XCTAssertEqual(store.selectedDevice, device)
        XCTAssertFalse(store.canUseResources)
    }

    @MainActor func testUnchangedEnumerationPreservesIdentityAndTaskResults() {
        let store = selectedStore(confirmed: true)
        store.successful = true
        store.status = "备份完成"
        store.backupPath = "/tmp/backup"
        store.errorMessage = "保留任务提示"
        store.applyDeviceList(store.devices)
        XCTAssertTrue(store.canUseResources)
        XCTAssertTrue(store.successful)
        XCTAssertEqual(store.status, "备份完成")
        XCTAssertEqual(store.backupPath, "/tmp/backup")
        XCTAssertEqual(store.errorMessage, "保留任务提示")
    }

    @MainActor func testMultipleInterfacesDoNotChooseAnArbitraryDevice() {
        let store = UpdaterStore()
        let first = DeviceInfo(pathHex: "first", productString: "K2", manufacturerString: nil,
                               serialNumber: nil, interfaceNumber: 0)
        let second = DeviceInfo(pathHex: "second", productString: "K2", manufacturerString: nil,
                                serialNumber: nil, interfaceNumber: 1)
        store.applyDeviceList([first, second])
        XCTAssertEqual(store.selectedPath, "")
        store.selectedPath = "second"
        store.applyDeviceList([second, first])
        XCTAssertEqual(store.selectedDevice, second)
    }

    @MainActor func testDFUConnectionDoesNotRequireManualConfirmation() {
        let store = selectedStore()
        store.dfuConfirmed = false
        XCTAssertTrue(store.canProbe)
        XCTAssertFalse(store.canUseResources)
        store.identity = IdentityInfo(bootStrings: ["K2"], infoSha256: "test", confirmedK2: true,
                                      currentVersion: "5.8", currentMarkerHex: nil)
        XCTAssertFalse(store.canUseResources)
        store.dfuConfirmed = true
        XCTAssertTrue(store.canUseResources)
        store.deviceChanged()
        XCTAssertNil(store.identity)
        XCTAssertFalse(store.dfuConfirmed)
        XCTAssertFalse(store.canUseResources)
    }

    @MainActor func testConnectingWithoutAnInterfaceShowsWarning() {
        let store = UpdaterStore()
        store.probe()
        XCTAssertNotNil(store.errorMessage)
        XCTAssertNil(store.operation)
        XCTAssertFalse(store.canUseResources)
    }

    func testFirmwareProgressResetsBetweenPhasesAndDoesNotResetDuringFlash() {
        XCTAssertEqual(FirmwareProgressPhase.firstBackup.progress(stage: "backup-read", fraction: 1), 1)
        XCTAssertEqual(FirmwareProgressPhase.checkBackup.progress(stage: "backup-verify", fraction: 0), 0)
        XCTAssertEqual(FirmwareProgressPhase.checkBackup.progress(stage: "backup-recovery", fraction: 0), 1)
        XCTAssertEqual(FirmwareProgressPhase.upgrade.progress(stage: "log-reset", fraction: 0), 0)
        let stages = [("erase", 0.0), ("erase", 1.0), ("write", 0.0), ("write", 1.0),
                      ("verify", 0.0), ("verify", 1.0), ("commit", 0.0), ("complete", 0.0)]
        let progress = stages.map { FirmwareProgressPhase.upgrade.progress(stage: $0.0, fraction: $0.1) }
        XCTAssertEqual(progress, progress.sorted())
        XCTAssertEqual(progress.last, 1)
    }

    func testWizardUsesAdjacentSlidesAndContinuesIntoNextTask() {
        XCTAssertEqual(FirmwareSlideRoute.destination(from: 0, to: 1), 1)
        XCTAssertEqual(FirmwareSlideRoute.destination(from: 1, to: 2), 2)
        XCTAssertEqual(FirmwareSlideRoute.destination(from: 2, to: 1), 1)
        XCTAssertEqual(FirmwareSlideRoute.destination(from: 1, to: 0), 0)
        XCTAssertEqual(FirmwareSlideRoute.destination(from: 3, to: 0), 4)
        // A rapid next click during the new-task slide returns to the real strip.
        XCTAssertEqual(FirmwareSlideRoute.destination(from: 4, to: 1), 1)
    }

    @MainActor func testNewUpgradeClearsPreviousTaskLogButKeepsDiagnosticFile() {
        let store = UpdaterStore()
        store.tracePath = "/tmp/probe.jsonl"
        XCTAssertNil(store.firmwareTaskTracePath)
        store.firmwareWizardStep = 3
        store.firmwareTaskTracePath = "/tmp/upgrade.jsonl"
        store.tracePath = "/tmp/upgrade.jsonl"
        store.firmwareWizardStep = 0
        XCTAssertNil(store.firmwareTaskTracePath)
        XCTAssertEqual(store.tracePath, "/tmp/upgrade.jsonl")
    }

    @MainActor private func selectedStore(confirmed: Bool = false) -> UpdaterStore {
        let store = UpdaterStore()
        store.devices = [DeviceInfo(pathHex: "test", productString: "K2", manufacturerString: nil,
                                    serialNumber: nil, interfaceNumber: 0)]
        store.selectedPath = "test"
        store.dfuConfirmed = true
        if confirmed {
            store.identity = IdentityInfo(bootStrings: ["K2"], infoSha256: "test", confirmedK2: true,
                                          currentVersion: "5.8", currentMarkerHex: nil)
        }
        return store
    }

    @MainActor func testUSBEnumerationDoesNotUnlockNext() {
        let store = selectedStore()
        XCTAssertFalse(store.canUseResources)
        store.advanceFirmwareWizard(to: 1)
        XCTAssertEqual(store.firmwareWizardStep, 0)
        XCTAssertNil(store.operation)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor func testMissingInterfaceAndActiveCaptureBlockAdvance() {
        let store = selectedStore(confirmed: true)
        store.selectedPath = ""
        store.advanceFirmwareWizard(to: 1)
        XCTAssertEqual(store.firmwareWizardStep, 0)
        XCTAssertNil(store.operation)
        store.selectedPath = "test"
        store.monitorConnected = true
        store.advanceFirmwareWizard(to: 1)
        XCTAssertEqual(store.firmwareWizardStep, 0)
        XCTAssertNil(store.operation)
    }

    @MainActor func testUnverifiedAndDemoFirmwareCannotAdvanceToUpgrade() {
        let store = selectedStore(confirmed: true)
        store.firmwareWizardStep = 1
        store.advanceFirmwareWizard(to: 2)
        XCTAssertEqual(store.firmwareWizardStep, 1)
        XCTAssertNil(store.operation)
        store.firmware = FirmwareInfo(model: "K2", version: "5.9", date: "2026-10-10",
                                      appSize: 100000, fileSha256: "test", eraseSectors: 49)
        store.isDemoFirmware = true
        store.advanceFirmwareWizard(to: 2)
        XCTAssertEqual(store.firmwareWizardStep, 1)
        XCTAssertNil(store.operation)
    }
}
