import SwiftUI

struct ConnectionSidebar: View {
    @ObservedObject var updater: UpdaterStore
    @ObservedObject var monitor: MonitorStore
    let section: ToolSection
    @Binding var expanded: Bool
    // Page navigation deliberately does not change this preparation selection.
    @State private var mode = "normal"

    private var summary: ConnectionPresentation { .current(updater: updater, monitor: monitor) }
    private var occupied: Bool { updater.isBusy || monitor.connected }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("设备连接").font(.headline)
                    Spacer()
                    Button { expanded = false } label: { Image(systemName: "sidebar.right") }
                        .buttonStyle(.plain).help("收起连接栏").accessibilityLabel("收起连接栏")
                }
                Label(summary.title, systemImage: summary.symbol)
                    .foregroundStyle(summary.color).font(.callout.weight(.medium))
                deviceSelection
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("连接用途").font(.subheadline.weight(.semibold))
                    Picker("连接用途", selection: $mode) {
                        Text("正常采集").tag("normal")
                        Text("DFU 维护").tag("dfu")
                    }.pickerStyle(.segmented).labelsHidden().disabled(occupied)
                    if monitor.connected || mode == "normal" { normalControls }
                    else { dfuControls }
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("设备信息").font(.subheadline.weight(.semibold))
                    LabeledContent("型号", value: updater.identity?.confirmedK2 == true ? "K2 已确认" : "未读取")
                    LabeledContent("固件版本", value: updater.identity?.currentVersion ?? "未读取")
                    if let identity = updater.identity, let boot = identity.bootStrings.last {
                        Text(boot).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }.font(.caption)
                taskHint
                if let error = monitor.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                        Button("关闭错误提示") { monitor.errorMessage = nil }
                    }
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(width: 260)
    }

    private var deviceSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("设备接口").font(.subheadline.weight(.semibold))
                Spacer()
                Button { updater.refreshDevices() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(occupied).help("刷新设备").accessibilityLabel("刷新设备")
            }
            Picker("设备接口", selection: $updater.selectedPath) {
                Text("选择 K2 接口").tag("")
                ForEach(updater.devices) { device in
                    Text("\(device.title) · 接口 \(device.interfaceNumber ?? 0)").tag(device.pathHex)
                }
            }.labelsHidden().disabled(occupied)
                .onChange(of: updater.selectedPath) { _ in updater.deviceChanged() }
            if let device = updater.selectedDevice {
                Text(device.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            } else {
                Text("未发现或未选择接口，请检查数据线及 CC1/HID 口。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var normalControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("正常开机，从 CC1/HID 口接入，不按减号键。").font(.caption).foregroundStyle(.secondary)
            if monitor.connected {
                Button(monitor.disconnecting ? "正在保存并断开…" : "断开采集连接") { monitor.disconnect() }
                    .disabled(monitor.disconnecting).frame(maxWidth: .infinity)
                Text("断开时会提交当前记录。切换页面不会中断采集。").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("连接并预览") { monitor.connect() }
                    .buttonStyle(.borderedProminent).disabled(updater.isBusy || updater.selectedDevice == nil)
                Text("连接用途只是操作准备，不会自动切换设备模式。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var dfuControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("按住减号键，从 CC1/HID 口连接，进入 DFU。").font(.caption).foregroundStyle(.secondary)
            Toggle("已按住减号键连接，进入 DFU", isOn: $updater.dfuConfirmed)
                .font(.callout).disabled(occupied)
            Button("读取设备信息") { updater.probe() }.disabled(!updater.canProbe)
            Text("读取成功后才允许设备备份和写入。").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var taskHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("当前页面", systemImage: section.symbol).font(.subheadline.weight(.semibold))
            Text(section == .monitor
                 ? (updater.canUseResources ? "当前已确认 DFU。采集需重新正常开机，选择正常采集后连接。" : "上位机使用正常模式。连接后可查看曲线、开始记录。")
                 : (monitor.connected ? "当前仍在采集。设备维护需先断开采集，再进入 DFU 并读取设备信息。本地编辑可继续。"
                    : "设备读写需要 DFU。选择 DFU 维护并读取信息；表盘、开机图和 E-Mark 可离线编辑。"))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(10).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
}
