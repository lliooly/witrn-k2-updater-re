import AppKit
import Combine
import Foundation
import K2Core
import UniformTypeIdentifiers

@MainActor
final class MonitorStore: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var disconnecting = false
    @Published private(set) var state: MonitorStatus?
    @Published private(set) var query: MonitorQuery?
    @Published private(set) var records: [MonitorRecord] = []
    @Published private(set) var fileBusy = false
    @Published private(set) var querying = false
    @Published private(set) var controlPending = false
    @Published private(set) var latest: MonitorSample?
    @Published var message = "正常模式连接 K2，从 CC1/HID 口接入；不按减号键"
    @Published var errorMessage: String?
    @Published var rate = 10
    @Published var follow = true
    @Published var windowSeconds: Double = 60
    @Published var rangeStart: Double = 0
    @Published var rangeEnd: Double = 60
    @Published var selectedRange = false
    @Published var autoEnabled = false
    @Published var autoKind = "current"
    @Published var threshold: Double = 0.05
    @Published var duration: Double = 30
    @Published var channels: Set<MonitorChannel> = [.voltage, .current, .power]
    private(set) var recordPath: String?
    private var previewPath: String?
    private let capture = BackendClient()
    private let files = BackendClient()
    private let reader = BackendClient()
    private weak var updater: UpdaterStore?
    private var timer: AnyCancellable?
    private var closeAction: (() -> Void)?
    private var queryGeneration = 0
    private var pendingQuery: (Bool, Bool)?
    var recording: Bool { state?.recording == true }
    var paused: Bool { state?.paused == true }
    var displayedPath: String? { connected && (!recording || paused) ? previewPath : recordPath ?? previewPath }
    var points: [MonitorSample] { query?.points ?? [] }

    func attach(_ updater: UpdaterStore) {
        guard self.updater == nil else { return }
        self.updater = updater
        listRecords()
        timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self, self.connected, self.follow, !self.selectedRange, !self.querying, !self.disconnecting else { return }
            self.refreshChart(stats: false)
        }
    }

    private func request(_ operation: BackendOperation) -> BackendRequest {
        BackendRequest(operation: operation, dataDirectory: updater?.dataDirectory.path ?? "")
    }

    func connect() {
        guard let updater, !updater.isBusy, !connected, let device = updater.selectedDevice else { return }
        var req = request(.monitor); req.devicePathHex = device.pathHex; req.deviceSerial = device.serialNumber
        connected = true; updater.monitorConnected = true; updater.identity = nil; updater.dfuConfirmed = false
        recordPath = nil; previewPath = nil; state = nil; latest = nil; query = nil; errorMessage = nil; selectedRange = false; follow = true
        message = "正在等待普通模式遥测…"
        do {
            try capture.start(req, onEvent: { [weak self] event in
                guard let self else { return }
                if event.event == "monitor", let value = event.value {
                    do {
                        let update = try value.decoded(MonitorStatus.self)
                        if let path = update.previewPath { self.previewPath = path }
                        if let path = update.recordPath { self.recordPath = path }
                        self.state = update
                        if let sample = update.latest { self.latest = sample }
                        if update.controlAck != nil { self.controlPending = false }
                        if let notice = update.notice {
                            self.message = notice
                            if update.controlAck != nil { self.errorMessage = notice }
                        }
                        else { self.message = update.stale == true ? "遥测已过期，正在检查连接" : (update.recording ? (update.paused ? "记录已暂停，实时预览继续" : "正在记录") : "实时预览") }
                    } catch { self.errorMessage = error.localizedDescription; self.disconnect() }
                } else if event.event == "error" { self.errorMessage = event.message }
                else if event.event == "result", let value = event.value {
                    if let path = value["record_path"]?.string { self.recordPath = path }
                }
            }, onFinish: { [weak self] code, error in
                guard let self else { return }
                self.connected = false; self.disconnecting = false; self.controlPending = false
                self.updater?.monitorConnected = false; self.previewPath = nil
                if let error { self.errorMessage = error.localizedDescription }
                if code != 0, self.errorMessage == nil { self.errorMessage = "采集后台已停止（\(code)）" }
                self.message = "连接已关闭，已提交的记录保留在文件中"
                self.state = nil; self.latest = nil; self.queryGeneration += 1
                self.refreshChart(stats: true); self.listRecords()
                let action = self.closeAction; self.closeAction = nil
                if code == 0, error == nil { action?() }
            })
        } catch {
            connected = false; updater.monitorConnected = false; errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        guard connected, !disconnecting else { return }
        disconnecting = true
        capture.cancelReadOnly()
    }

    private func control(_ fields: [String: JSONValue]) {
        guard connected, !disconnecting, !controlPending else { return }
        do { try capture.sendControl(fields); controlPending = true }
        catch { errorMessage = error.localizedDescription }
    }

    func startRecording() {
        guard connected, !recording, let updater else { return }
        guard threshold.isFinite, threshold >= 0, duration.isFinite, !autoEnabled || duration > 0 else {
            errorMessage = "阈值必须非负，自动停止持续时间必须大于零"; return
        }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "K2-\(Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-" )).sqlite"
        panel.message = "选择新记录的位置。已有文件不会被覆盖。"
        panel.directoryURL = updater.dataDirectory.appendingPathComponent("Recordings")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        control(["command": .string("start"), "path": .string(url.path), "rate": .number(Double(rate)),
                 "auto_kind": .string(autoKind), "threshold": .number(threshold), "duration": .number(autoEnabled ? duration : 0)])
        selectedRange = false; follow = true; queryGeneration += 1
    }
    func pauseResume() { control(["command": .string(paused ? "resume" : "pause")]) }
    func stopRecording() { control(["command": .string("stop")]) }
    func clearPreview() {
        // Start a fresh passive preview; existing recording files remain intact.
        guard connected, !recording else { return }
        closeAction = { [weak self] in self?.query = nil; self?.recordPath = nil; self?.connect() }
        disconnect()
    }

    func refreshChart(stats: Bool = true, overview: Bool = false) {
        guard let path = displayedPath else { return }
        if querying {
            pendingQuery = (stats, overview); queryGeneration += 1; reader.cancelReadOnly(); return
        }
        var req = request(.monitorQuery); req.recordPath = path; req.includeStats = stats
        if !overview {
            if selectedRange { req.rangeStart = rangeStart; req.rangeEnd = rangeEnd }
            else if follow, connected, let time = latest?.time {
                req.rangeStart = max(0, time - windowSeconds)
            } else if !follow { req.rangeStart = rangeStart; req.rangeEnd = rangeEnd }
        }
        let generation = queryGeneration
        querying = true
        var result: MonitorQuery?
        var failure: String?
        do {
            try reader.start(req, onEvent: { event in
                if event.event == "result", let value = event.value { result = try? value.decoded(MonitorQuery.self) }
                if event.event == "error" { failure = event.message }
            }, onFinish: { [weak self] code, error in
                guard let self else { return }
                self.querying = false
                let pending = self.pendingQuery; self.pendingQuery = nil
                defer { if let pending { self.refreshChart(stats: pending.0, overview: pending.1) } }
                guard generation == self.queryGeneration, path == self.displayedPath else { return }
                if let result {
                    self.query = result
                    if overview { self.follow = false; self.selectedRange = false; self.rangeStart = result.start ?? 0; self.rangeEnd = result.end ?? 1 }
                    else if self.follow && !self.selectedRange { self.rangeStart = result.rangeStart ?? 0; self.rangeEnd = result.rangeEnd ?? 1 }
                } else if code != 130, stats { self.errorMessage = error?.localizedDescription ?? failure ?? "记录查询失败" }
            })
        } catch { querying = false; errorMessage = error.localizedDescription }
    }
    func select(_ start: Double, _ end: Double) {
        guard start.isFinite, end.isFinite, start >= 0, end >= 0 else {
            errorMessage = "区间起止时间必须是有限且非负的秒数"; return
        }
        rangeStart = min(start, end); rangeEnd = max(start, end)
        follow = false; selectedRange = true
        queryGeneration += 1
        refreshChart()
    }
    func zoom(_ factor: Double) {
        let middle = (rangeStart + rangeEnd) / 2, half = max(0.01, (rangeEnd - rangeStart) * factor / 2)
        select(max(query?.start ?? 0, middle - half), min(query?.end ?? middle + half, middle + half))
    }
    func move(_ direction: Double) {
        let width = max(0.01, rangeEnd - rangeStart)
        let start = max(query?.start ?? 0, min((query?.end ?? rangeEnd) - width, rangeStart + width * direction / 2))
        select(start, start + width)
    }

    func listRecords() {
        guard updater != nil, !fileBusy else { return }
        fileOperation(request(.monitorList)) { [weak self] value in
            self?.records = (try? value["records"]?.decoded([MonitorRecord].self)) ?? []
        }
    }
    func open(_ url: URL? = nil) {
        guard !fileBusy else { return }
        if connected {
            let alert = NSAlert(); alert.messageText = recording ? "停止保存并打开历史记录？" : "断开预览并打开历史记录？"
            alert.addButton(withTitle: "停止并打开"); alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            closeAction = { [weak self] in self?.open(url) }; disconnect(); return
        }
        let chosen: URL
        if let url { chosen = url }
        else {
            let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
            panel.message = "选择官方 CSV、SQLite 或本地记录；导入会创建副本"
            guard panel.runModal() == .OK, let value = panel.url else { return }; chosen = value
        }
        var req = request(.monitorImport); req.recordPath = chosen.path
        req.outputPath = updater?.dataDirectory.appendingPathComponent("Recordings/\(UUID().uuidString).sqlite").path
        fileOperation(req) { [weak self] value in
            self?.loadPath(value["path"]?.string)
        }
    }
    func openSaved(_ record: MonitorRecord) {
        guard !connected, !fileBusy else { return }
        loadPath(record.path)
        if record.unfinished { message = "该记录未正常结束，已提交的数据仍可查看或导出" }
    }
    private func loadPath(_ path: String?) {
        recordPath = path; selectedRange = false; follow = false; queryGeneration += 1
        refreshChart(stats: true, overview: true)
    }
    func export(_ kind: String, selection: Bool = false) {
        guard !fileBusy, let path = recordPath ?? previewPath else { return }
        if kind != "local-sqlite" {
            let alert = NSAlert(); alert.messageText = "导出官方兼容格式"
            alert.informativeText = "保留电压、有符号电流、非负功率、外部温度及 D±。分段、内部温度和扩展字段不会保存；需要完整数据请另存本地 SQLite。"
            alert.addButton(withTitle: "导出"); alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "K2-record.\(kind == "csv" ? "csv" : "sqlite")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var req = request(.monitorExport); req.recordPath = path; req.outputPath = url.path; req.exportKind = kind
        if selection { req.rangeStart = rangeStart; req.rangeEnd = rangeEnd }
        fileOperation(req) { [weak self] value in self?.message = "已导出：\(value["path"]?.string ?? url.path)" }
    }
    private func fileOperation(_ req: BackendRequest, success: @escaping (JSONValue) -> Void) {
        guard !fileBusy else { return }
        fileBusy = true; errorMessage = nil
        var result: JSONValue?; var failure: String?
        do {
            try files.start(req, onEvent: { event in
                if event.event == "result" { result = event.value }
                if event.event == "error" { failure = event.message }
            }, onFinish: { [weak self] code, error in
                guard let self else { return }; self.fileBusy = false
                if code == 0, let result { success(result) }
                else if code != 130 { self.errorMessage = error?.localizedDescription ?? failure ?? "文件操作失败" }
            })
        } catch { fileBusy = false; errorMessage = error.localizedDescription }
    }
    func cancelFiles() { files.cancelReadOnly() }
    func reveal() { if let path = displayedPath { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } }

    func prepareClose(_ action: @escaping () -> Void) -> Bool {
        if fileBusy { errorMessage = "请先等待或取消文件操作，再关闭应用"; return false }
        guard connected else { return true }
        let alert = NSAlert(); alert.messageText = recording ? "停止记录并保存后关闭？" : "断开采集后关闭？"
        alert.informativeText = "应用会等待后台提交记录并关闭设备接口。"
        alert.addButton(withTitle: "保存并关闭"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        closeAction = action; disconnect(); return false
    }
}
