import XCTest
@testable import K2Updater

final class OfficialFirmwareTests: XCTestCase {
    func testLatestVersionComesFromOfficialFirmwareLinksAndNumericOrder() throws {
        let html = """
        <a href="https://www.witrn.com/witrn/K2/K2_V5.9.zip">K2 固件包 V5.9</a>
        <a class="download" href='/witrn/K2/K2_V5.10.zip'><strong>K2 固件包 V5.10</strong></a>
        <a href="https://other.example/witrn/K2/K2_V9.0.zip">K2 固件包 V9.0</a>
        <a href="https://www.witrn.com/witrn/K2/K2_V8.0.zip">升级工具</a>
        """
        let release = try OfficialFirmwareService.latest(in: html)
        XCTAssertEqual(release.version, "5.10")
        XCTAssertEqual(release.downloadURL.absoluteString, "https://www.witrn.com/witrn/K2/K2_V5.10.zip")
    }

    func testMissingOrChangedPageDoesNotInventARelease() {
        XCTAssertThrowsError(try OfficialFirmwareService.latest(in: "<h1>暂无固件</h1>"))
        XCTAssertThrowsError(try OfficialFirmwareService.latest(in:
            "<a href='https://other.example/K2_V5.8.zip'>K2 固件包 V5.8</a>"))
    }

    func testOnlyOfficialHTTPSOriginsAreAccepted() {
        XCTAssertTrue(OfficialFirmwareService.allowed(URL(string: "https://www.witrn.com/witrn/K2/K2_V5.8.zip")!))
        for address in ["http://www.witrn.com/file.zip", "https://www.witrn.com.other.example/file.zip",
                        "https://user@www.witrn.com/file.zip", "https://www.witrn.com:8443/file.zip"] {
            XCTAssertFalse(OfficialFirmwareService.allowed(URL(string: address)!))
        }
    }
}
