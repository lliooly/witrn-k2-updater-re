import AppKit
import Combine
import Foundation
import K2Core
import CryptoKit

struct ResourceWriteIntent: Identifiable {
    let id = UUID()
    let kind: PictureResource
    let data: Data?
    let manifest: URL?
    let manifestHash: String?
    var restoring: Bool { manifest != nil }
}

@MainActor
final class UpdaterStore: ObservableObject {
    @Published var dfuConfirmed = false
    @Published var devices: [DeviceInfo] = []
    @Published var selectedPath = ""
    @Published var identity: IdentityInfo?
    @Published var firmware: FirmwareInfo?
    @Published var firmwareURL: URL?
    @Published var isDemoFirmware = false
    @Published var isBusy = false
    @Published var monitorConnected = false
    @Published var operation: BackendOperation?
    @Published var stage = "preflight"
    @Published var current = 0
    @Published var total = 0
    @Published var status = "等待 K2 连接"
    @Published var errorMessage: String?
    @Published var successful = false
    @Published var firmwareWizardStep = 0
    @Published var backupPath: String?
    @Published var tracePath: String?
    private let backend = BackendClient()
    private let deviceChecker = BackendClient()
    private var checkingDevices = false
    private var pendingFirmwareStep: Int?
    private var pendingResult: JSONValue?
    private var receivedError = false
    private var resourceReadResult: ((URL, PictureResource) -> Void)?
    let dataDirectory: URL

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--data-dir"), args.indices.contains(index + 1) {
            dataDirectory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
        } else {
            dataDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("K2 Updater", isDirectory: true)
        }
    }

    var selectedDevice: DeviceInfo? { devices.first { $0.pathHex == selectedPath } }
    var canProbe: Bool { !isBusy && !monitorConnected && selectedDevice != nil && dfuConfirmed }
    var canUpgrade: Bool {
        canProbe && identity?.confirmedK2 == true && firmware != nil && !isDemoFirmware
    }
    var canCancel: Bool { isBusy && operation?.canCancel == true }
    var canUseResources: Bool { canProbe && identity?.confirmedK2 == true }
    var progress: Double { total > 0 ? min(1, Double(current) / Double(total)) : 0 }

    func deviceChanged() { identity = nil }
    func refreshDevices() { run(.devices) }
    func probe() { run(.probe) }
    func advanceFirmwareWizard(to step: Int) {
        guard (1...2).contains(step), canUseResources, step != 2 || canUpgrade else { return }
        pendingFirmwareStep = step
        run(.probe)
    }

    /// Enumerate without resetting task results or touching a device interface.
    func checkDevicePresence() {
        guard !isBusy, !checkingDevices else { return }
        checkingDevices = true
        var listedDevices: [DeviceInfo]?
        do {
            try deviceChecker.start(BackendRequest(operation: .devices, dataDirectory: dataDirectory.path),
                onEvent: { event in
                    if event.event == "result" {
                        listedDevices = try? event.value?["devices"]?.decoded([DeviceInfo].self)
                    }
                }, onFinish: { [weak self] code, _ in
                    guard let self else { return }
                    self.checkingDevices = false
                    guard !self.isBusy else { return }
                    guard code == 0, let devices = listedDevices else { self.identity = nil; return }
                    self.applyDeviceList(devices)
                })
        } catch { checkingDevices = false }
    }

    func applyDeviceList(_ discovered: [DeviceInfo]) {
        let previous = selectedDevice
        if devices != discovered { devices = discovered }
        if selectedDevice == nil {
            let path = !monitorConnected && discovered.count == 1 ? discovered[0].pathHex : ""
            if selectedPath != path { selectedPath = path }
        }
        if selectedDevice != previous || selectedDevice == nil {
            if identity != nil { identity = nil }
            if dfuConfirmed { dfuConfirmed = false }
        }
    }
    func backup() { run(.backup) }
    func inspect(_ url: URL) { guard !isBusy else { return }; firmware = nil; firmwareURL = url; run(.inspect) }
    func importOfficialFirmware(_ archive: URL, version: String) {
        guard !isBusy else { return }
        firmware = nil; firmwareURL = archive
        run(.firmwareExtract, firmwareVersion: version)
    }
    func upgrade() { run(.upgrade, confirmed: true) }
    func readResource(_ kind: PictureResource, receive: @escaping (URL, PictureResource) -> Void) {
        guard canUseResources else { return }
        resourceReadResult = receive
        run(.resourceRead, resource: kind)
    }
    func writeResource(_ intent: ResourceWriteIntent) {
        guard canUseResources else { return }
        do {
            if let manifest = intent.manifest {
                run(.resourceRestore, confirmed: true, resource: intent.kind, payload: manifest, digest: intent.manifestHash)
            } else if let data = intent.data {
                let directory = dataDirectory.appendingPathComponent("Prepared", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("\(intent.id).resource")
                try data.write(to: url, options: .atomic)
                run(.resourceWrite, confirmed: true, resource: intent.kind, payload: url, digest: Self.digest(data))
            }
        } catch { errorMessage = error.localizedDescription }
    }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    func chooseResourceBackup() -> ResourceWriteIntent? {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = "选择资源备份目录中的 manifest.json"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            guard ((try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max) <= 65536 else { throw PictureError.invalid("资源备份清单过大") }
            let data = try Data(contentsOf: url)
            guard let info = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  info["type"] as? String == "k2-resource-backup", info["schema"] as? Int == 1,
                  let name = info["kind"] as? String, let kind = PictureResource(rawValue: name) else {
                throw PictureError.invalid("请选择本应用生成的资源备份清单")
            }
            return ResourceWriteIntent(kind: kind, data: nil, manifest: url, manifestHash: Self.digest(data))
        } catch { errorMessage = error.localizedDescription; return nil }
    }
    func cancel() { guard canCancel else { return }; status = "正在停止只读操作…"; backend.cancelReadOnly() }

    private func run(_ action: BackendOperation, confirmed: Bool = false, resource: PictureResource? = nil,
                     payload: URL? = nil, digest: String? = nil, firmwareVersion: String? = nil) {
        guard !isBusy else { return }
        guard !monitorConnected || action == .devices || action == .inspect || action == .firmwareExtract else {
            errorMessage = "请先在曲线页面断开采集，再进行设备维护操作"; return
        }
        var request = BackendRequest(operation: action, dataDirectory: dataDirectory.path)
        request.firmwarePath = firmwareURL?.path
        request.firmwareVersion = firmwareVersion
        request.firmwareSha256 = firmware?.fileSha256
        request.devicePathHex = selectedDevice?.pathHex
        request.deviceSerial = selectedDevice?.serialNumber
        request.deviceInfoSha256 = identity?.infoSha256
        request.dfuConfirmed = dfuConfirmed; request.confirmed = confirmed
        if action == .probe { identity = nil }
        request.resourceKind = resource?.rawValue
        if action == .resourceRestore { request.restoreManifestPath = payload?.path; request.restoreManifestSha256 = digest }
        else { request.resourcePath = payload?.path; request.resourceSha256 = digest }
        if action != .devices && action != .inspect && action != .firmwareExtract { tracePath = nil; backupPath = nil }
        operation = action; isBusy = true; receivedError = false; pendingResult = nil
        errorMessage = nil; successful = false; stage = "preflight"; current = 0; total = 0
        status = "正在处理"
        do {
            try backend.start(request, onEvent: { [weak self] in self?.receive($0) },
                              onFinish: { [weak self] code, error in self?.finish(code, error) })
        } catch { finish(1, error) }
    }

    private func receive(_ event: BackendEvent) {
        switch event.event {
        case "progress":
            stage = event.stage ?? stage; current = event.current ?? 0; total = event.total ?? 0
            status = StageTitle.text(stage)
        case "paths":
            if let backup = event.backup { backupPath = backup }
            if let trace = event.trace { tracePath = trace }
        case "identity":
            if let value = event.identity { identity = try? value.decoded(IdentityInfo.self) }
        case "result": pendingResult = event.value
        case "error":
            receivedError = true
            errorMessage = event.cancelled == true ? nil : (event.message ?? "后台操作失败")
            status = event.cancelled == true ? "已取消只读操作" : "\(StageTitle.text(event.stage ?? stage))失败"
        default: break
        }
    }

    private func finish(_ code: Int32, _ error: Error?) {
        defer { isBusy = false; operation = nil; resourceReadResult = nil; pendingFirmwareStep = nil }
        if let error { errorMessage = error.localizedDescription; receivedError = true }
        guard code == 0, !receivedError, let value = pendingResult else {
            if code != 130 && errorMessage == nil { errorMessage = "后台未正常完成（退出码 \(code)）" }
            if code != 130 { status = "操作已停止" }
            if operation?.isWrite == true { identity = nil; dfuConfirmed = false }
            return
        }
        do {
            switch operation {
            case .devices:
                applyDeviceList(try value["devices"]?.decoded([DeviceInfo].self) ?? [])
                status = devices.isEmpty ? "未发现 K2，请检查数据线及 CC1/HID 口" : "已发现 \(devices.count) 个接口"
            case .inspect, .firmwareExtract:
                firmware = try value["firmware"]?.decoded(FirmwareInfo.self)
                if let path = value["firmware_path"]?.string { firmwareURL = URL(fileURLWithPath: path) }
                isDemoFirmware = value["demo_firmware"]?.bool == true
                status = "固件检查通过"
                if isDemoFirmware { errorMessage = "这是合成固件，不能写入设备" }
            case .probe:
                identity = try value["identity"]?.decoded(IdentityInfo.self)
                status = "设备读取完成 · 当前版本 \(identity?.currentVersion ?? "未知")"
                if identity?.confirmedK2 == true, let step = pendingFirmwareStep {
                    firmwareWizardStep = step
                }
            case .backup:
                identity = try value["identity"]?.decoded(IdentityInfo.self)
                backupPath = value["backup"]?["directory"]?.string
                status = "备份完成，两遍读取一致"; successful = true
            case .upgrade:
                backupPath = value["backup"]?["directory"]?.string
                status = "固件 \(firmware?.version ?? "") 已写入并校验，请重新上电确认"
                successful = true
                firmwareWizardStep = 3
                identity = nil; dfuConfirmed = false
            case .resourceRead:
                backupPath = value["backup"]?["directory"]?.string
                if value["resource_valid"]?.bool == true,
                   let path = value["resource_path"]?.string,
                   let name = value["resource_kind"]?.string, let kind = PictureResource(rawValue: name) {
                    resourceReadResult?(URL(fileURLWithPath: path), kind)
                    status = "\(kind.title)已读取，两遍备份一致"; successful = true
                } else {
                    status = "原始资源已备份"
                    errorMessage = value["resource_error"]?.string ?? "设备尚未设置有效资源"
                }
            case .resourceWrite, .resourceRestore:
                backupPath = value["backup"]?["directory"]?.string
                status = "资源已写入，完整扇区读回一致。请重新上电确认。"; successful = true
                identity = nil; dfuConfirmed = false
            default: break
            }
            if let trace = value["trace"]?.string { tracePath = trace }
        } catch { errorMessage = "后台结果解析失败：\(error.localizedDescription)"; status = "操作已停止" }
    }

    func showBackup() { if let backupPath { NSWorkspace.shared.open(URL(fileURLWithPath: backupPath)) } }
    func showLog() { if let tracePath { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: tracePath)]) } }
}
