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
            VStack(alignment: .leading, spacing: 20) {
                Text(titles[step]).font(.title2.weight(.semibold))
                switch step {
                case 0: preparation
                case 1: firmwareSelection
                case 2: upgrade
                default: completion
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))

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
        }
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
            Label("屏幕显示 K2 DFU 后，选择接口并检测。检测成功才可继续。", systemImage: "info.circle")
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
            }.disabled(store.isBusy || store.monitorConnected)
            Toggle("已按住减号键连接，屏幕显示 K2 DFU", isOn: $store.dfuConfirmed)
                .disabled(store.isBusy || store.monitorConnected)
            Button { store.probe() } label: { Label("检测 DFU 并读取设备", systemImage: "info.circle") }
                .buttonStyle(.borderedProminent).disabled(!store.canProbe)
            if store.isBusy { ProgressView(store.status).controlSize(.small) }
            if store.canUseResources {
                Label("DFU 检测通过 · K2 · 当前固件 \(store.identity?.currentVersion ?? "未知")", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if store.identity != nil {
                Label("设备型号未确认，请检查接口和 DFU 状态。", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if store.devices.isEmpty && !store.isBusy {
                Text("未发现设备，请检查数据线和 CC1/HID 接口。连接后会自动刷新。")
                    .font(.callout).foregroundStyle(.secondary)
            } else if !store.isBusy {
                Text("尚未通过 DFU 检测，暂时不能进入下一步。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if store.monitorConnected {
                Button("打开连接栏，断开采集") { showConnection() }
            }
        }
    }

    private var firmwareSelection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("使用官网最新固件，或选择本地 .k2 文件。校验通过后才能继续。")
            officialFirmwareCard
            FirmwareCard(store: store).disabled(official.downloading)
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
            HStack {
                Text("官网固件").font(.headline)
                Spacer()
                Link("打开官网", destination: OfficialFirmwareService.pageURL).font(.caption)
            }
            if official.checking {
                ProgressView("正在检查官网最新版本…").controlSize(.small)
            } else if let release = official.release {
                HStack(spacing: 12) {
                    Text("当前 \(store.identity?.currentVersion ?? "未知")")
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text("官网 V\(release.version)").fontWeight(.semibold)
                }
                if store.identity?.currentVersion == release.version {
                    Text("设备已是官网当前发布版本。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if official.downloading {
                    ProgressView("正在下载官网固件…").controlSize(.small)
                } else {
                    Button("下载并使用 V\(release.version)") {
                        Task {
                            await official.download(to: store.dataDirectory) { archive, version in
                                store.importOfficialFirmware(archive, version: version)
                            }
                        }
                    }.buttonStyle(.borderedProminent).disabled(store.isBusy)
                }
            }
            if let error = official.errorMessage {
                Text(error).font(.callout).foregroundStyle(.orange)
            }
            Button("重新检查") { Task { await official.check() } }
                .disabled(official.checking || official.downloading || store.isBusy)
                .font(.caption)
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
                Text(store.status).font(.headline)
                if store.total > 0 { ProgressView(value: store.progress) }
                else { ProgressView().controlSize(.small) }
            } else {
                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).textSelection(.enabled)
                    Text("操作已停止。请返回“进入 DFU”重新检查连接后再继续。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("返回 DFU 检测") { step = 0 }
                }
                HStack {
                    Button("仅备份") { store.backup() }.disabled(!store.canUseResources)
                    Spacer()
                    Button("备份并升级") { confirmUpgrade = true }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(!store.canUpgrade)
                }
                if store.successful, store.backupPath != nil, store.canUseResources {
                    Label("备份完成，两遍读取一致。", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("打开备份") { store.showBackup() }
                }
            }
            if store.errorMessage != nil, store.tracePath != nil {
                Button("查看日志") { store.showLog() }
            }
        }
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("固件 \(store.firmware?.version ?? "") 已写入并通过校验", systemImage: "checkmark.circle.fill")
                .font(.title3).foregroundStyle(.green)
            Text("拔下数据线，再不按任何按键重新上电。请在设备屏幕上确认版本和正常运行状态。")
            Text("应用已保存升级前的备份。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
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
        Text("⚠ " + (store.monitorConnected ? "设备维护不可用：请先在连接栏断开采集，再进入 DFU 并读取设备信息"
             : store.isBusy ? "设备任务正在进行，完成后可继续操作"
             : "设备操作需要在右侧连接栏选择 DFU 维护、确认接入方式并读取设备信息"))
            .font(.callout)
            .foregroundStyle(.red)
    }
}
