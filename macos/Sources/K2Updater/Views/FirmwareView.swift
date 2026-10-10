import AppKit
import SwiftUI

struct FirmwareView: View {
    @ObservedObject var store: UpdaterStore
    let showConnection: () -> Void
    private var step: Int {
        get { store.firmwareWizardStep }
        nonmutating set { store.firmwareWizardStep = newValue }
    }
    @State private var confirmUpgrade = false
    @State private var showIllustration = false
    @State private var slidesMoving = false
    @State private var firmwareSource = "official"
    @StateObject private var official = OfficialFirmwareStore()
    private let titles = ["进入 DFU", "选择固件", "备份并升级", "完成"]
    private let manualURL = URL(string: "https://github.com/JohnScotttt/WITRN-K2-Quick-Reference-Manual#7-固件类")!

    private var illustration: NSImage? {
        guard let url = Bundle.module.url(forResource: "DFU", withExtension: "png", subdirectory: "Resources") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 8) {
                ForEach(titles.indices, id: \.self) { index in
                    VStack(spacing: 8) {
                        Text(index < step ? "✓" : "\(index + 1)")
                            .font(.callout.weight(.semibold))
                            .frame(width: 30, height: 30)
                            .foregroundStyle(index <= step ? Color.white : Color.secondary)
                            .background(index < step ? Color.green : index == step ? Color.accentColor : Color.gray.opacity(0.12), in: Circle())
                        Text(titles[index]).font(.caption)
                            .foregroundStyle(index == step ? .primary : .secondary)
                    }.frame(maxWidth: .infinity)
                }
            }
            Divider()
            FirmwareSlideDeck(step: step, isMoving: $slidesMoving) { index in
                VStack(alignment: .leading, spacing: 20) {
                    Text(titles[index]).font(.title2.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: index == 3 ? .center : .leading)
                    switch index {
                    case 0: preparation
                    case 1: firmwareSelection
                    case 2: upgrade
                    default: completion
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if step != 2, let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }

            HStack {
                if step > 0 && step < 3 {
                    Button("上一步") { step -= 1 }.disabled(store.isBusy || official.downloading)
                }
                Spacer()
                if step == 0 {
                    Button("下一步：选择固件") { store.advanceFirmwareWizard(to: 1) }
                        .buttonStyle(.borderedProminent).disabled(!store.canUseResources)
                } else if step == 1 {
                    Button("下一步：确认升级") { store.advanceFirmwareWizard(to: 2) }
                        .buttonStyle(.borderedProminent).disabled(!store.canUpgrade || official.downloading)
                } else if step == 3 {
                    Button("开始新的升级") { step = 0 }.buttonStyle(.borderedProminent).disabled(store.isBusy)
                }
            }
            .disabled(slidesMoving)
        }
        .buttonBorderShape(.roundedRectangle)
        .task(id: step) {
            if step == 1 { await official.checkIfNeeded() }
        }
        .onChange(of: store.isBusy) { busy in
            guard !busy else { return }
            if step == 1 && !store.canUseResources {
                step = 0
            }
        }
        .alert("备份并升级到 \(store.firmware?.version ?? "")？", isPresented: $confirmUpgrade) {
            Button("取消", role: .cancel) {}
            Button("确认升级") {
                guard store.canUpgrade else { return }
                store.upgrade()
            }
        } message: {
            Text("当前 \(store.identity?.currentVersion ?? "未知") → 目标 \(store.firmware?.version ?? "未知")。升级期间请保持连接")
        }
        .sheet(isPresented: $showIllustration) {
            VStack(spacing: 16) {
                if let illustration {
                    Image(nsImage: illustration).resizable().scaledToFit()
                        .padding(16).background(.white)
                }
                Button("关闭") { showIllustration = false }.keyboardShortcut(.cancelAction)
            }.padding(24).frame(width: 900, height: 420)
        }
    }

    private var preparation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("先断开设备电源。数据线一端连接电脑，按住 K2 的减号键，同时把另一端插入 CC1/HID 接口。")
                .font(.body).fixedSize(horizontal: false, vertical: true)
            if let illustration {
                Button { showIllustration = true } label: {
                    Image(nsImage: illustration).resizable().scaledToFit()
                        .frame(maxHeight: 250).padding(12)
                        .frame(maxWidth: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).help("点击放大示意图").accessibilityLabel("放大进入 DFU 模式示意图")
            }
            HStack {
                Text("图片来源：JohnScotttt · GPL-3.0").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Link("查看原手册", destination: manualURL).font(.caption)
            }
            Label("屏幕显示 K2 DFU 后，点击连接设备，应用会自动检查接口和 DFU 状态。", systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
            deviceDetection
            if store.monitorConnected {
                Label("采集仍在运行，请先在连接栏断开采集。", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("打开连接栏") { showConnection() }
            }
        }
    }

    private var deviceDetection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("设备接口", selection: $store.selectedPath) {
                    Text("选择 K2 接口").tag("")
                    ForEach(store.devices) { device in
                        Text("\(device.title) · 接口 \(device.interfaceNumber ?? 0)").tag(device.pathHex)
                    }
                }
                .onChange(of: store.selectedPath) { _ in store.deviceChanged() }
                Button { store.probe() } label: { Label("连接设备", systemImage: "cable.connector") }
                    .buttonStyle(.borderedProminent)
            }.disabled(store.isBusy || store.monitorConnected)
            if store.isBusy { ProgressView(store.status).controlSize(.small) }
            if store.canUseResources {
                Label("DFU 检测通过 · K2 · 当前固件 \(store.identity?.currentVersion ?? "未知")", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if store.monitorConnected {
                Button("打开连接栏，断开采集") { showConnection() }
            }
        }
    }

    private var firmwareSelection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("使用官网最新固件，或选择本地 .k2 文件。校验通过后才能继续。")
            AnimatedSegmentedPicker(title: "固件来源", selection: $firmwareSource,
                                    options: [("official", "官网固件"), ("manual", "手动上传")])
                .disabled(store.isBusy || official.downloading)
                .onChange(of: firmwareSource) { _ in
                    store.firmware = nil
                    store.firmwareURL = nil
                    store.isDemoFirmware = false
                    store.errorMessage = nil
                }
            if firmwareSource == "official" {
                officialFirmwareCard
            } else {
                FirmwareCard(store: store).disabled(store.isBusy)
            }
            versionComparison
            if store.isBusy { ProgressView(store.status).controlSize(.small) }
            if store.isDemoFirmware {
                Label("这是演示固件，请重新选择真实固件。", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var officialFirmwareCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let release = official.release {
                    Text("检查到版本：V\(release.version)").fontWeight(.semibold)
                    Button("下载并使用") {
                        Task {
                            await official.download(to: store.dataDirectory) { archive, version in
                                store.importOfficialFirmware(archive, version: version)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isBusy || official.checking || official.downloading)
                }
                Button("重新检查") { Task { await official.check() } }
                    .disabled(official.checking || official.downloading || store.isBusy)
                Spacer(minLength: 0)
            }
            if official.checking {
                ProgressView("正在检查官网最新版本…").controlSize(.small)
            }
            if official.downloading {
                ProgressView("正在下载官网固件…").controlSize(.small)
            }
            if let release = official.release, store.identity?.currentVersion == release.version {
                Text("设备已是官网当前发布版本。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = official.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            Link("打开官网", destination: OfficialFirmwareService.pageURL).font(.caption)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var versionComparison: some View {
        HStack(spacing: 24) {
            versionDisplay("当前版本", store.identity?.currentVersion ?? "未读取")
            Image(systemName: "arrow.right").foregroundStyle(.secondary)
            versionDisplay("目标版本", store.firmware?.version ?? "未选择")
            Spacer()
        }
    }

    private var upgrade: some View {
        VStack(alignment: .leading, spacing: 16) {
            versionComparison
            Label("应用会先读取两遍并核对备份，再写入固件并读回校验。", systemImage: "externaldrive.badge.checkmark")
            Label("升级期间请保持数据线连接，不要断电。", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            if store.isBusy {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.firmwareProgressPhase.title).font(.headline)
                    ProgressView(value: store.firmwarePhaseProgress)
                    Text(store.status).font(.caption).foregroundStyle(.secondary)
                }
                .id(store.firmwareProgressPhase)
            } else {
                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).textSelection(.enabled)
                    Text("操作已停止。请返回“进入 DFU”重新检查连接后再继续。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("返回 DFU 检测") { step = 0 }
                }
                HStack(spacing: 12) {
                    Button("仅备份") { store.backup() }
                        .controlSize(.large).disabled(!store.canUseResources)
                    Button("备份并升级") { confirmUpgrade = true }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(!store.canUpgrade)
                }
                if store.successful, store.backupPath != nil, store.canUseResources {
                    Label("备份完成，两遍读取一致。", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("打开备份") { store.showBackup() }
                }
            }
            FirmwareLogConsole(path: store.firmwareTaskTracePath, active: step == 2)
        }
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 12) {
                FirmwareSuccessAnimation(active: step == 3)
                Text("升级完成").font(.title3.weight(.semibold)).foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity)
            Text("拔下数据线，再不按任何按键重新上电。请在设备屏幕上确认版本和正常运行状态。")
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            HStack {
                Spacer()
                Button("打开备份") { store.showBackup() }.disabled(store.backupPath == nil)
                Button("查看日志") { store.showLog() }.disabled(store.tracePath == nil)
            }
        }
    }

    private func versionDisplay(_ label: String, _ version: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(version).font(.title3.weight(.medium))
        }
    }
}

struct ResourceAvailabilityHint: View {
    @ObservedObject var store: UpdaterStore
    var body: some View {
        Text("⚠ " + (store.monitorConnected ? "设备维护不可用：请先在连接栏断开采集，再进入 DFU 并连接设备"
             : store.isBusy ? "设备任务正在进行，完成后可继续操作"
             : "设备操作需要在右侧连接栏选择 DFU 维护、连接设备并通过自动检测"))
            .font(.callout)
            .foregroundStyle(.red)
    }
}

private struct FirmwareSuccessAnimation: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle().fill(.green)
                .scaleEffect(appeared ? 1 : 0.05)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: appeared)
            FirmwareCheckmark()
                .trim(from: 0, to: appeared ? 1 : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .padding(22)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.35).delay(0.3), value: appeared)
        }
        .frame(width: 88, height: 88)
        .accessibilityHidden(true)
        .task(id: active) {
            if active { appeared = true; return }
            // Keep the completed checkmark intact while its page slides away.
            do { try await Task.sleep(nanoseconds: 350_000_000) }
            catch { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { appeared = false }
        }
    }
}

private struct FirmwareCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.5))
            path.addLine(to: CGPoint(x: rect.width * 0.35, y: rect.height * 0.8))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.15))
        }
    }
}
