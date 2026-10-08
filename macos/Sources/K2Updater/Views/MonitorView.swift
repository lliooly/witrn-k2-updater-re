import AppKit
import SwiftUI
import K2Core

struct MonitorView: View {
    @ObservedObject var monitor: MonitorStore
    @ObservedObject var updater: UpdaterStore
    let showConnection: () -> Void
    @SceneStorage("monitorWorkspace") private var workspace = "live"
    @SceneStorage("monitorExtraReadings") private var extraReadings = false
    @SceneStorage("monitorStatisticsExpanded") private var statisticsExpanded = false
    private var interval: ClosedRange<Double>? {
        guard monitor.selectedRange, monitor.rangeStart.isFinite, monitor.rangeEnd.isFinite,
              monitor.rangeEnd >= monitor.rangeStart else { return nil }
        return monitor.rangeStart...monitor.rangeEnd
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Picker("工作区", selection: $workspace) {
                        Text("实时").tag("live")
                        Text("历史记录").tag("history")
                    }.pickerStyle(.segmented).frame(width: 220)
                    Spacer()
                    Button("打开 / 导入…") { monitor.open() }.disabled(monitor.fileBusy)
                    exportMenu
                }
                if let error = monitor.errorMessage {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(error).textSelection(.enabled)
                        Spacer()
                        Button("关闭") { monitor.errorMessage = nil }
                    }.font(.callout).padding(10).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                if monitor.fileBusy {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("正在处理记录文件…")
                        Spacer()
                        Button("取消") { monitor.cancelFiles() }
                    }.font(.caption)
                }
                if workspace == "live" {
                    readings
                    MonitorRecordingControls(monitor: monitor)
                } else {
                    historyView
                }
                if let path = monitor.displayedPath {
                    HStack {
                        Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "doc.text")
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("定位文件") { monitor.reveal() }
                    }.font(.caption).foregroundStyle(.secondary)
                }
                chartControls
                charts
                statistics
            }.padding(20)
        }
        .onChange(of: monitor.selectedRange) { selected in if selected { statisticsExpanded = true } }
    }

    private var readings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                reading("电压", monitor.latest?.voltage, "V")
                reading("电流", monitor.latest?.current, "A")
                reading("功率", monitor.latest?.power, "W")
            }.opacity(monitor.state?.stale == true ? 0.4 : 1)
            DisclosureGroup("更多实时读数", isExpanded: $extraReadings) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("内部温度 \(MonitorFormat.number(monitor.latest?.tempIn)) °C · 外部温度 \(MonitorFormat.number(monitor.latest?.tempOut)) °C")
                    Text("D+ \(MonitorFormat.number(monitor.latest?.dp)) V · D− \(MonitorFormat.number(monitor.latest?.dn)) V")
                    Text("设备累计 \(MonitorFormat.number(monitor.latest?.ah)) Ah · \(MonitorFormat.number(monitor.latest?.wh)) Wh")
                    Text("记录组 \(monitor.latest?.group.map(String.init) ?? "—") · 设备记录 \(deviceTime(monitor.latest?.recordSeconds)) · 开机 \(deviceTime(monitor.latest?.uptime))")
                    Text("接收 \(MonitorFormat.number(monitor.state?.receiveRate, digits: 1))/s · 已记录 \(monitor.state?.recordCount ?? 0)")
                    if let invalid = monitor.state?.invalid, invalid > 0 {
                        Text("已忽略 \(invalid) 个无效遥测包").foregroundStyle(.orange)
                    }
                }.font(.caption.monospacedDigit()).padding(.top, 6)
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(14).background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }
    private func deviceTime(_ seconds: Int?) -> String { seconds.map { MonitorFormat.elapsed(Double($0)) } ?? "—" }
    private func reading(_ title: String, _ value: Double?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(MonitorFormat.number(value)) \(unit)").font(.title.monospacedDigit())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exportMenu: some View {
        Menu("导出") {
            Menu("全部记录") { exportItems(selection: false) }.disabled(monitor.displayedPath == nil || monitor.fileBusy)
            Menu("选中区间") { exportItems(selection: true) }.disabled(!monitor.selectedRange || monitor.fileBusy)
            Divider()
            Button("保存曲线 PNG…") { saveChart() }.disabled(monitor.points.isEmpty)
        }.fixedSize()
    }
    @ViewBuilder private func exportItems(selection: Bool) -> some View {
        Button("官方兼容 CSV…") { monitor.export("csv", selection: selection) }
        Button("官方兼容 SQLite…") { monitor.export("official-sqlite", selection: selection) }
        Button("完整本地 SQLite…") { monitor.export("local-sqlite", selection: selection) }
    }

    private var chartControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack { timeControls; Spacer(); navigationControls }
                VStack(alignment: .leading, spacing: 8) { timeControls; navigationControls }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(MonitorChannel.allCases) { channel in
                    Toggle(channel.title, isOn: Binding(get: { monitor.channels.contains(channel) }, set: { enabled in
                        if enabled { monitor.channels.insert(channel) } else { monitor.channels.remove(channel) }
                    })).toggleStyle(.checkbox)
                }
            }.font(.caption)
        }
    }
    private var timeControls: some View {
        HStack {
            Toggle("跟随最新", isOn: $monitor.follow).onChange(of: monitor.follow) { value in
                if value { monitor.selectedRange = false; monitor.refreshChart(stats: false) }
            }.disabled(!monitor.connected)
            Picker("窗口", selection: $monitor.windowSeconds) {
                Text("1 分钟").tag(60.0); Text("5 分钟").tag(300.0); Text("30 分钟").tag(1800.0)
            }.frame(width: 140)
        }.disabled(monitor.displayedPath == nil || monitor.querying)
    }
    private var navigationControls: some View {
        HStack {
            Button("全程概览") { monitor.refreshChart(stats: true, overview: true) }
            Button("−") { monitor.zoom(2) }.help("缩小").accessibilityLabel("缩小曲线")
            Button("+") { monitor.zoom(0.5) }.help("放大").accessibilityLabel("放大曲线")
            Button("←") { monitor.move(-1) }.help("向前移动").accessibilityLabel("向前移动曲线")
            Button("→") { monitor.move(1) }.help("向后移动").accessibilityLabel("向后移动曲线")
            if monitor.querying { ProgressView().controlSize(.small) }
        }.disabled(monitor.displayedPath == nil || monitor.querying)
    }
    @ViewBuilder private var charts: some View {
        if !monitor.points.isEmpty {
            if monitor.channels.isEmpty { Text("请选择至少一个曲线通道。").foregroundStyle(.secondary) }
            ForEach(MonitorChannel.allCases.filter { monitor.channels.contains($0) }) { channel in
                MonitorChart(points: monitor.points, channel: channel,
                             start: monitor.query?.rangeStart ?? monitor.rangeStart,
                             end: monitor.query?.rangeEnd ?? monitor.rangeEnd,
                             selection: interval, onSelect: monitor.select)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "chart.xyaxis.line").font(.system(size: 38)).foregroundStyle(.secondary)
                Text(monitor.connected ? "等待有效遥测与曲线数据" : "连接 K2 或打开历史记录")
                if !monitor.connected {
                    Button("设备连接") { showConnection() }
                    Button("打开历史记录…") { monitor.open() }.disabled(monitor.fileBusy)
                }
            }.frame(maxWidth: .infinity).frame(height: 220)
        }
    }
    private var statistics: some View {
        DisclosureGroup("区间统计", isExpanded: $statisticsExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("起止秒数")
                    TextField("开始", value: $monitor.rangeStart, format: .number).frame(width: 85)
                    Text("—")
                    TextField("结束", value: $monitor.rangeEnd, format: .number).frame(width: 85)
                    Button("计算统计") { monitor.select(monitor.rangeStart, monitor.rangeEnd) }
                        .disabled(monitor.querying || monitor.displayedPath == nil)
                }
                Text("也可直接拖选曲线；统计使用原始样本计算。").font(.caption).foregroundStyle(.secondary)
                if let statistics = monitor.query?.statistics {
                    ScrollView(.horizontal) { MonitorStatisticsView(statistics: statistics) }
                }
            }.padding(.top, 8)
        }
    }
    private var historyView: some View {
        GroupBox("本地记录") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("选择记录查看曲线和统计").foregroundStyle(.secondary)
                    Spacer()
                    Button("刷新列表") { monitor.listRecords() }.disabled(monitor.fileBusy)
                }
                if monitor.connected {
                    Text("当前采集仍在运行。打开 / 导入可确认停止并保存；查看列表中的记录需要先断开采集。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if monitor.records.isEmpty {
                    Text("默认目录暂无记录，其他位置的文件可通过打开 / 导入查看。").foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(monitor.records) { record in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(URL(fileURLWithPath: record.path).lastPathComponent).lineLimit(1)
                                    Text("\(record.count) 样本\(record.unfinished ? " · 未正常结束" : "")")
                                        .foregroundStyle(record.unfinished ? .orange : .secondary)
                                }
                                Spacer()
                                Button("查看") { monitor.openSaved(record) }.disabled(monitor.connected || monitor.fileBusy)
                            }.font(.caption)
                        }
                    }
                }.frame(maxHeight: 180)
            }.padding(8)
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
