import SwiftUI

struct ConnectionSidebar: View {
    @ObservedObject var updater: UpdaterStore
    @ObservedObject var monitor: MonitorStore
    let section: ToolSection
    // Page navigation deliberately does not change this preparation selection.
    @State private var mode = "normal"

    private var summary: ConnectionPresentation { .current(updater: updater, monitor: monitor) }
    private var occupied: Bool { updater.isBusy || monitor.connected }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("设备连接").font(.title3.weight(.semibold))
                    Label(summary.title, systemImage: summary.symbol)
                        .foregroundStyle(summary.color).font(.callout.weight(.medium))
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(summary.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                deviceSelection
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("连接用途").font(.callout.weight(.semibold))
                    Picker("连接用途", selection: $mode) {
                        Text("正常采集").tag("normal")
                        Text("DFU 维护").tag("dfu")
                    }.pickerStyle(.segmented).labelsHidden().disabled(occupied)
                    if monitor.connected || mode == "normal" { normalControls }
                    else { dfuControls }
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("设备信息").font(.callout.weight(.semibold))
                    VStack(alignment: .leading, spacing: 6) {
                        infoRow("型号", updater.identity?.confirmedK2 == true ? "K2 已确认" : "未读取")
                        infoRow("固件版本", updater.identity?.currentVersion ?? "未读取")
                    }
                    if let identity = updater.identity, let boot = identity.bootStrings.last {
                        Text(boot).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                taskHint
                if let error = monitor.errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                        }
                        Button("关闭错误提示") { monitor.errorMessage = nil }
                    }.padding(10).background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(width: 260)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }.font(.callout)
    }

    private var deviceSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("设备接口").font(.callout.weight(.semibold))
                Spacer()
                Button { updater.refreshDevices() } label: {
                    Image(systemName: "arrow.clockwise")
                }.disabled(occupied).help("刷新设备").accessibilityLabel("刷新设备")
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
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                    Text("未发现或未选择接口，请检查数据线及 CC1/HID 口").font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    private var normalControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill").foregroundStyle(.blue).font(.caption)
                Text("正常开机，从 CC1/HID 口接入，不按减号键").font(.caption).foregroundStyle(.blue)
            }
            if monitor.connected {
                Button { monitor.disconnect() } label: {
                    Label(monitor.disconnecting ? "正在保存并断开…" : "断开采集连接", systemImage: "xmark.circle")
                }.disabled(monitor.disconnecting).frame(maxWidth: .infinity)
                Text("断开时会提交当前记录。切换页面不会中断采集").font(.caption).foregroundStyle(.secondary)
            } else {
                Button { monitor.connect() } label: {
                    Label("连接并预览", systemImage: "cable.connector")
                }.buttonStyle(.borderedProminent).disabled(updater.isBusy || updater.selectedDevice == nil)
            }
        }
    }

    private var dfuControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                Text("按住减号键，从 CC1/HID 口连接，进入 DFU").font(.caption).foregroundStyle(.orange)
            }
            Toggle("已按住减号键连接，进入 DFU", isOn: $updater.dfuConfirmed)
                .font(.callout).disabled(occupied)
            Button { updater.probe() } label: {
                Label("读取设备信息", systemImage: "info.circle")
            }.disabled(!updater.canProbe).frame(maxWidth: .infinity)
            Text("读取成功后才允许设备备份和写入").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var taskHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: section.symbol).foregroundStyle(.blue)
                Text("当前页面").font(.callout.weight(.semibold)).foregroundStyle(.blue)
            }
            Text(section == .monitor
                 ? (updater.canUseResources ? "当前已确认 DFU。采集需重新正常开机，选择正常采集后连接" : "上位机使用正常模式。连接后可查看曲线、开始记录")
                 : (monitor.connected ? "当前仍在采集。设备维护需先断开采集，再进入 DFU 并读取设备信息。本地编辑可继续"
                    : "设备读写需要 DFU。选择 DFU 维护并读取信息；表盘、开机图和 E-Mark 可离线编辑"))
                .font(.callout).foregroundStyle(.secondary)
        }.padding(12).background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
