import SwiftUI
import K2Core

struct ConnectionSidebar: View {
    @ObservedObject var updater: UpdaterStore
    @ObservedObject var monitor: MonitorStore
    @ObservedObject var picture: PictureStore
    let section: ToolSection
    // Page navigation deliberately does not change this preparation selection.
    @State private var mode = "normal"
    @State private var writeIntent: ResourceWriteIntent?

    private var occupied: Bool { updater.isBusy || monitor.connected }
    private var isDialOrStartup: Bool { section == .dial || section == .startup }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("设备连接").font(.title3.weight(.semibold))

                deviceSelection
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("连接用途").font(.callout.weight(.semibold))
                    AnimatedSegmentedPicker(title: "连接用途", selection: $mode,
                                            options: [("normal", "正常采集"), ("dfu", "DFU 维护")])
                        .disabled(occupied)
                    if monitor.connected || mode == "normal" { normalControls }
                    else { dfuControls }
                }

                // 设备操作（仅表盘和开机图页面）
                if isDialOrStartup {
                    Divider()
                    deviceOperations
                }

                if mode == "dfu" {
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
                }
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
        }
        .buttonBorderShape(.roundedRectangle)
        .frame(width: LayoutMetrics.connectionSidebarWidth)
        .frame(maxHeight: .infinity)
        .modifier(SystemGlassSurface())
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
                }.disabled(monitor.disconnecting).frame(maxWidth: .infinity, alignment: .leading)
                Text("断开时会提交当前记录。切换页面不会中断采集").font(.caption).foregroundStyle(.secondary)
            } else {
                Button { monitor.connect() } label: {
                    Label("连接设备", systemImage: "cable.connector")
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
            Button { updater.probe() } label: {
                Label("连接设备", systemImage: "cable.connector")
            }
            .buttonStyle(.borderedProminent)
            .disabled(occupied)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let error = updater.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
        }
    }

    // 设备操作部分（表盘/开机图）
    private var deviceOperations: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设备操作")
                .font(.callout)
                .fontWeight(.semibold)

            if section == .dial {
                resourceButtons(.layout)
                Divider()
                resourceButtons(.background)
            } else if section == .startup {
                resourceButtons(.startup)
            }

            if !updater.canUseResources {
                Text("⚠ 需进入 DFU 模式")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("⚠ " + (section == .startup ? "每次写入后重新进入 DFU" : "每次完成后重新进入 DFU"))
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .alert("\(writeIntent?.restoring == true ? "恢复" : "写入")\(writeIntent?.kind.title ?? "资源")？",
               isPresented: Binding(get: { writeIntent != nil }, set: { if !$0 { writeIntent = nil } })) {
            Button("取消", role: .cancel) { writeIntent = nil }
            Button("确认") {
                if let intent = writeIntent { updater.writeResource(intent) }
                writeIntent = nil
            }
        } message: {
            Text("先读取目标资源并备份，再擦除、写入并校验")
        }
    }

    private func resourceButtons(_ kind: PictureResource) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(kind.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("读取") {
                    updater.readResource(kind) { picture.acceptRead($0, kind: $1) }
                }
                .disabled(!updater.canUseResources)
                .font(.caption)

                Button("写入") {
                    do {
                        writeIntent = ResourceWriteIntent(
                            kind: kind,
                            data: try picture.resourceData(kind),
                            manifest: nil,
                            manifestHash: nil
                        )
                    }
                    catch {
                        picture.error = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!updater.canUseResources ||
                         (kind == .background && picture.project.background == nil) ||
                         (kind == .startup && picture.project.startup == nil))
                .font(.caption)
            }
        }
    }
}
