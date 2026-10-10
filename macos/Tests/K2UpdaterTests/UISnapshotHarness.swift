import AppKit
import SwiftUI
import XCTest
@testable import K2Updater
@testable import K2Core

/// Development-only offscreen renderer used to inspect layout while refactoring.
/// Set K2_SNAPSHOT_DIR to write PNGs; otherwise the test is a no-op.
final class UISnapshotHarness: XCTestCase {
    @MainActor
    func testRenderWorkspaceScrollEdges() throws {
        guard let dir = ProcessInfo.processInfo.environment["K2_SNAPSHOT_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for scheme: ColorScheme in [.light, .dark] {
            applyAppearance(scheme)
            for offset: CGFloat in [0, 180] {
                render(ContentView(store: UpdaterStore(), picture: PictureStore(), emark: EmarkStore(),
                                   monitor: MonitorStore(), selection: .constant(.firmware)),
                       size: CGSize(width: 1280, height: 720),
                       name: "scroll-edge-\(scheme)-\(Int(offset))", scheme: scheme, dir: dir,
                       scrollOffset: offset, nativeTitlebar: true)
            }
        }
    }

    @MainActor
    func testRenderFirmwareWizard() throws {
        guard let dir = ProcessInfo.processInfo.environment["K2_SNAPSHOT_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let updater = UpdaterStore()
        updater.devices = [DeviceInfo(pathHex: "test", productString: "K2", manufacturerString: nil,
                                     serialNumber: nil, interfaceNumber: 0)]
        updater.selectedPath = "test"
        updater.dfuConfirmed = true
        updater.identity = IdentityInfo(bootStrings: ["K2"], infoSha256: "", confirmedK2: true,
                                        currentVersion: "5.8", currentMarkerHex: nil)
        updater.firmware = FirmwareInfo(model: "K2", version: "5.9", date: "2026-10-10",
                                       appSize: 100000, fileSha256: "", eraseSectors: 49)
        for scheme: ColorScheme in [.light, .dark] {
            applyAppearance(scheme)
            for step in 0...3 {
                updater.firmwareWizardStep = step
                render(FirmwareView(store: updater, showConnection: {}).padding(24),
                       size: CGSize(width: 740, height: 720),
                       name: "firmware-\(scheme)-\(step)", scheme: scheme, dir: dir)
            }
            updater.firmwareWizardStep = 2
            updater.isBusy = true
            updater.status = "读回校验"
            updater.total = 100
            updater.current = 60
            render(FirmwareView(store: updater, showConnection: {}).padding(24),
                   size: CGSize(width: 620, height: 720), name: "firmware-\(scheme)-busy",
                   scheme: scheme, dir: dir)
            updater.isBusy = false
            updater.identity = nil
            updater.dfuConfirmed = false
            updater.errorMessage = "设备连接已断开，固件写入未完成"
            render(FirmwareView(store: updater, showConnection: {}).padding(24),
                   size: CGSize(width: 620, height: 720), name: "firmware-\(scheme)-failure",
                   scheme: scheme, dir: dir)
            updater.errorMessage = nil
            updater.dfuConfirmed = true
            updater.identity = IdentityInfo(bootStrings: ["K2"], infoSha256: "", confirmedK2: true,
                                            currentVersion: "5.8", currentMarkerHex: nil)
        }
    }

    @MainActor
    private func applyAppearance(_ scheme: ColorScheme) {
        NSApplication.shared.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    }

    @MainActor
    func testRenderMonitor() throws {
        guard let dir = ProcessInfo.processInfo.environment["K2_SNAPSHOT_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let monitor = MonitorStore()
        let updater = UpdaterStore()
        let picture = PictureStore()
        let emark = EmarkStore()
        let scheme: ColorScheme = ProcessInfo.processInfo.environment["K2_SNAPSHOT_LIGHT"] != nil ? .light : .dark
        applyAppearance(scheme)

        render(ContentView(store: updater, picture: picture, emark: emark, monitor: monitor,
                           selection: .constant(.monitor)),
               size: CGSize(width: 1280, height: 880), name: "01-content-monitor", scheme: scheme, dir: dir)

        render(MonitorWorkspace(monitor: monitor, updater: updater, showConnection: {},
                                workspace: .constant("live"), extraReadings: .constant(false),
                                statisticsExpanded: .constant(false)),
               size: CGSize(width: 800, height: 860), name: "02-monitor-live", scheme: scheme, dir: dir)

        render(MonitorWorkspace(monitor: monitor, updater: updater, showConnection: {},
                                workspace: .constant("history"), extraReadings: .constant(true),
                                statisticsExpanded: .constant(false)),
               size: CGSize(width: 800, height: 860), name: "03-monitor-history", scheme: scheme, dir: dir)

        // Minimum usable width: the single control lines must not wrap.
        render(MonitorWorkspace(monitor: monitor, updater: updater, showConnection: {},
                                workspace: .constant("live"), extraReadings: .constant(false),
                                statisticsExpanded: .constant(false)),
               size: CGSize(width: 620, height: 860), name: "04-monitor-narrow", scheme: scheme, dir: dir)

        render(LocalRecordsCard(records: Self.records, busy: false, connected: false,
                                onRefresh: {}, onOpen: { _ in }, onClose: {}),
               size: CGSize(width: 760, height: 190), name: "06-local-records", scheme: scheme, dir: dir)

        render(LocalRecordsCard(records: [], busy: false, connected: false,
                                onRefresh: {}, onOpen: { _ in }, onClose: {}),
               size: CGSize(width: 760, height: 120), name: "07-local-records-empty", scheme: scheme, dir: dir)
    }

    @MainActor
    func testRenderDenseMonitorCharts() throws {
        guard let dir = ProcessInfo.processInfo.environment["K2_SNAPSHOT_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let points = try MonitorChartTests.samples()
        applyAppearance(.light)
        render(MonitorPlotExport(points: points, channels: [.voltage, .current, .tempOut],
                                 start: 0, end: 125),
               size: CGSize(width: 1100, height: 640), name: "08-dense-charts", scheme: .light, dir: dir)
    }

    @MainActor
    func testRenderOtherPages() throws {
        guard let dir = ProcessInfo.processInfo.environment["K2_SNAPSHOT_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let monitor = MonitorStore()
        let updater = UpdaterStore()
        let picture = PictureStore()
        let emark = EmarkStore()
        let scheme: ColorScheme = ProcessInfo.processInfo.environment["K2_SNAPSHOT_LIGHT"] != nil ? .light : .dark
        applyAppearance(scheme)

        for (name, section) in [("10-content-firmware", ToolSection.firmware),
                                ("11-content-emark", .emark),
                                ("12-content-dial", .dial),
                                ("13-content-startup", .startup)] {
            render(ContentView(store: updater, picture: picture, emark: emark, monitor: monitor,
                               selection: .constant(section)),
                   size: CGSize(width: 1280, height: 880), name: name, scheme: scheme, dir: dir)
        }
    }

    static var records: [MonitorRecord] {
        [
            MonitorRecord(path: "/Users/k2/Recordings/K2-2026-10-09-2041.sqlite", count: 18422,
                          start: 0, end: 1842.5, metadata: ["closed": "1"]),
            MonitorRecord(path: "/Users/k2/Recordings/K2-2026-10-08-1130.sqlite", count: 9210,
                          start: 0, end: 921.0, metadata: ["closed": "0"])
        ]
    }

    @MainActor
    private func render(_ view: some View, size: CGSize, name: String,
                        scheme: ColorScheme, dir: String, scrollOffset: CGFloat? = nil,
                        nativeTitlebar: Bool = false) {
        // Without an explicit opaque backdrop the capture keeps alpha, and the
        // default-coloured text becomes invisible against a white preview.
        let root = view
            .environment(\.colorScheme, scheme)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: nativeTitlebar ? [.titled, .closable, .resizable, .fullSizeContentView] : [.borderless],
                              backing: .buffered, defer: false)
        if nativeTitlebar {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
        }
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        let composite = nativeTitlebar && ProcessInfo.processInfo.environment["K2_COMPOSITED_SNAPSHOTS"] == "1"
        if composite { window.orderFront(nil) }
        defer { if composite { window.orderOut(nil) } }
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        hosting.layoutSubtreeIfNeeded()
        if let scrollOffset {
            func descendants(_ view: NSView) -> [NSScrollView] {
                (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(descendants)
            }
            let scroll = descendants(hosting)
                .filter { ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height }
                .max { $0.frame.width < $1.frame.width }
            if let scroll, let document = scroll.documentView {
                if nativeTitlebar && scrollOffset == 0 {
                    XCTAssertGreaterThanOrEqual(scroll.contentInsets.top, LayoutMetrics.navigationSidebarHeaderHeight,
                                                "The initial content must reserve the full workspace toolbar height.")
                    XCTAssertLessThanOrEqual(scroll.contentView.bounds.minY, -LayoutMetrics.navigationSidebarHeaderHeight,
                                             "The wizard must begin below the toolbar in a titled window.")
                }
                let maximum = max(0, document.frame.height - scroll.contentView.bounds.height)
                scroll.contentView.scroll(to: CGPoint(x: 0, y: min(scroll.contentView.bounds.minY + scrollOffset, maximum)))
                scroll.reflectScrolledClipView(scroll.contentView)
                RunLoop.main.run(until: Date().addingTimeInterval(0.5))
                hosting.layoutSubtreeIfNeeded()
            }
        }
        if composite {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(window.windowNumber),
                                 URL(fileURLWithPath: dir).appendingPathComponent("\(name)-composited.png").path]
            do {
                try capture.run()
                capture.waitUntilExit()
                XCTAssertEqual(capture.terminationStatus, 0, "Window compositor capture failed.")
            } catch { XCTFail("Window compositor capture failed: \(error)") }
        }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            XCTFail("no bitmap for \(name)"); return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            XCTFail("no png for \(name)"); return
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? png.write(to: url)
        print("wrote \(url.path)")
    }
}
