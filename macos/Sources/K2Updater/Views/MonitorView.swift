import AppKit
import SwiftUI
import K2Core

struct MonitorView: View {
    @ObservedObject var monitor: MonitorStore
    @ObservedObject var updater: UpdaterStore
    @State private var history = false
    private var interval: ClosedRange<Double>? {
        guard monitor.selectedRange, monitor.rangeStart.isFinite, monitor.rangeEnd.isFinite,
              monitor.rangeEnd >= monitor.rangeStart else { return nil }
        return monitor.rangeStart...monitor.rangeEnd
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("曲线与记录").font(.title2.bold())
                connection
                Text(monitor.message).font(.callout).foregroundStyle(.secondary)
                if let error = monitor.errorMessage {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(error).textSelection(.enabled)
                        Spacer(); Button("关闭") { monitor.errorMessage = nil }
                    }.padding(10).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                readings
                controls
                chartControls
                if !monitor.points.isEmpty {
                    ForEach(MonitorChannel.allCases.filter { monitor.channels.contains($0) }) { channel in
                        MonitorChart(points: monitor.points, channel: channel,
                                     start: monitor.query?.rangeStart ?? monitor.rangeStart,
                                     end: monitor.query?.rangeEnd ?? monitor.rangeEnd,
                                     selection: interval,
                                     onSelect: monitor.select)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.xyaxis.line").font(.system(size: 38)).foregroundStyle(.secondary)
                        Text(monitor.connected ? "等待有效遥测与曲线数据" : "连接 K2 或打开历史记录")
                    }.frame(maxWidth: .infinity).frame(height: 180)
                }
                if let statistics = monitor.query?.statistics { MonitorStatisticsView(statistics: statistics) }
                historyView
            }.padding(22)
        }.frame(minWidth: 775)
        .onAppear { monitor.attach(updater) }
    }

    private var connection: some View {
        GroupBox("正常模式 · 只读采集") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("设备", selection: $updater.selectedPath) {
                        Text("选择 K2 接口").tag("")
                        ForEach(updater.devices) { device in Text("\(device.title) · 接口 \(device.interfaceNumber ?? 0)").tag(device.pathHex) }
                    }.disabled(monitor.connected || updater.isBusy)
                    Button("刷新") { updater.refreshDevices() }.disabled(updater.isBusy || monitor.connected)
                    if monitor.connected {
                        Button(monitor.disconnecting ? "正在保存并断开…" : "断开") { monitor.disconnect() }.disabled(monitor.disconnecting)
                    } else {
                        Button("连接") { monitor.connect() }.buttonStyle(.borderedProminent).disabled(updater.isBusy || updater.selectedDevice == nil)
                    }
                }
                Text("K2 正常开机，从 CC1/HID 口使用数据线接入。采集期间设备维护操作不可用。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }
    }

    private var readings: some View {
        GroupBox("实时读数") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 25) {
                    reading("电压", monitor.latest?.voltage, "V")
                    reading("电流", monitor.latest?.current, "A")
                    reading("功率", monitor.latest?.power, "W")
                    reading("内部温度", monitor.latest?.tempIn, "°C")
                    reading("外部温度", monitor.latest?.tempOut, "°C")
                }.opacity(monitor.state?.stale == true ? 0.4 : 1)
                HStack {
                    Text("D+ \(MonitorFormat.number(monitor.latest?.dp)) V · D− \(MonitorFormat.number(monitor.latest?.dn)) V")
                    Spacer()
                    Text("设备累计 \(MonitorFormat.number(monitor.latest?.ah)) Ah · \(MonitorFormat.number(monitor.latest?.wh)) Wh")
                }
                HStack {
                    Text("记录组 \(monitor.latest?.group.map(String.init) ?? "—") · 设备记录 \(deviceTime(monitor.latest?.recordSeconds)) · 开机 \(deviceTime(monitor.latest?.uptime))")
                    Spacer()
                    Text("接收 \(MonitorFormat.number(monitor.state?.receiveRate, digits: 1))/s · 已记录 \(monitor.state?.recordCount ?? 0)")
                }
                if let state = monitor.state, let invalid = state.invalid, invalid > 0 { Text("已忽略 \(invalid) 个无效遥测包").foregroundStyle(.orange) }
            }.font(.caption.monospacedDigit()).padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func deviceTime(_ seconds: Int?) -> String { seconds.map { MonitorFormat.elapsed(Double($0)) } ?? "—" }
    private func reading(_ title: String, _ value: Double?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(MonitorFormat.number(value)) \(unit)").font(.title3.monospacedDigit())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        GroupBox("保存记录") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("电脑采样上限", selection: $monitor.rate) {
                        Text("1/s").tag(1); Text("10/s").tag(10); Text("100/s").tag(100); Text("全部接收").tag(0)
                    }.frame(width: 210).disabled(monitor.recording)
                    if monitor.recording {
                        Button(monitor.paused ? "继续记录" : "暂停记录") { monitor.pauseResume() }
                        Button("停止并保存") { monitor.stopRecording() }
                    } else {
                        Button("开始记录…") { monitor.startRecording() }.buttonStyle(.borderedProminent).disabled(!monitor.connected)
                    }
                    Spacer()
                    Button("定位文件") { monitor.reveal() }.disabled(monitor.displayedPath == nil)
                }.disabled(monitor.controlPending || monitor.disconnecting)
                HStack {
                    Toggle("自动停止", isOn: $monitor.autoEnabled)
                    Picker("条件", selection: $monitor.autoKind) { Text("|电流| (A)").tag("current"); Text("功率 (W)").tag("power") }.labelsHidden().frame(width: 115)
                    Text("低于")
                    TextField("阈值", value: $monitor.threshold, format: .number).frame(width: 65)
                    Text("连续")
                    TextField("秒", value: $monitor.duration, format: .number).frame(width: 65)
                    Text("秒后停止")
                }.font(.callout).disabled(monitor.recording)
                if monitor.fileBusy { HStack { ProgressView().controlSize(.small); Text("正在处理记录文件…"); Button("取消") { monitor.cancelFiles() } } }
                HStack {
                    Button("打开 / 导入…") { monitor.open() }.disabled(monitor.fileBusy)
                    Menu("导出全部") { exportItems(selection: false) }.disabled(monitor.displayedPath == nil || monitor.fileBusy)
                    Menu("导出选区") { exportItems(selection: true) }.disabled(!monitor.selectedRange || monitor.fileBusy)
                    Button("保存曲线 PNG…") { saveChart() }.disabled(monitor.points.isEmpty)
                    Spacer()
                    Button("清除预览") { monitor.clearPreview() }.disabled(!monitor.connected || monitor.recording || monitor.disconnecting)
                }
                Text("采样设置只限制电脑记录速率。暂停时实时预览继续；数据按真实时间保存。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8)
        }
    }
    @ViewBuilder private func exportItems(selection: Bool) -> some View {
        Button("官方兼容 CSV…") { monitor.export("csv", selection: selection) }
        Button("官方兼容 SQLite…") { monitor.export("official-sqlite", selection: selection) }
        Button("完整本地 SQLite…") { monitor.export("local-sqlite", selection: selection) }
    }

    private var chartControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("跟随最新", isOn: $monitor.follow).onChange(of: monitor.follow) { value in
                    if value { monitor.selectedRange = false; monitor.refreshChart(stats: false) }
                }.disabled(!monitor.connected)
                Picker("窗口", selection: $monitor.windowSeconds) {
                    Text("1 分钟").tag(60.0); Text("5 分钟").tag(300.0); Text("30 分钟").tag(1800.0)
                }.frame(width: 140)
                Button("全程概览") { monitor.refreshChart(stats: true, overview: true) }
                Button("−") { monitor.zoom(2) }.help("缩小")
                Button("+") { monitor.zoom(0.5) }.help("放大")
                Button("←") { monitor.move(-1) }; Button("→") { monitor.move(1) }
                Spacer()
                if monitor.querying { ProgressView().controlSize(.small) }
            }.disabled(monitor.displayedPath == nil || monitor.querying)
            HStack {
                Text("起止秒数")
                TextField("开始", value: $monitor.rangeStart, format: .number).frame(width: 100)
                Text("—")
                TextField("结束", value: $monitor.rangeEnd, format: .number).frame(width: 100)
                Button("区间统计") { monitor.select(monitor.rangeStart, monitor.rangeEnd) }.disabled(monitor.querying || monitor.displayedPath == nil)
                Text("也可直接拖选曲线").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                ForEach(MonitorChannel.allCases) { channel in
                    Toggle(channel.title, isOn: Binding(get: { monitor.channels.contains(channel) }, set: { enabled in
                        if enabled { monitor.channels.insert(channel) } else { monitor.channels.remove(channel) }
                    })).toggleStyle(.checkbox)
                }
            }.font(.caption)
        }
    }

    private var historyView: some View {
        DisclosureGroup("本地记录与未正常结束的记录", isExpanded: $history) {
            VStack(alignment: .leading, spacing: 8) {
                Button("刷新记录列表") { monitor.listRecords() }.disabled(monitor.fileBusy)
                if monitor.records.isEmpty { Text("默认记录目录中暂无记录；其他位置的文件可通过打开导入。").foregroundStyle(.secondary) }
                ForEach(monitor.records) { record in
                    HStack {
                        Text(URL(fileURLWithPath: record.path).lastPathComponent).lineLimit(1)
                        Text("\(record.count) 样本\(record.unfinished ? " · 未正常结束" : "")").foregroundStyle(record.unfinished ? .orange : .secondary)
                        Spacer()
                        Button("查看") { monitor.openSaved(record) }.disabled(monitor.connected || monitor.fileBusy)
                    }.font(.caption)
                }
            }.padding(.top, 8)
        }
    }

    @MainActor private func saveChart() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "K2-chart.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let renderer = ImageRenderer(content: MonitorPlotExport(points: monitor.points,
            channels: MonitorChannel.allCases.filter { monitor.channels.contains($0) }, start: monitor.query?.rangeStart ?? 0, end: monitor.query?.rangeEnd ?? 1))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            monitor.errorMessage = "曲线图片生成失败"; return
        }
        do { try png.write(to: url, options: .atomic) }
        catch { monitor.errorMessage = error.localizedDescription }
    }
}
