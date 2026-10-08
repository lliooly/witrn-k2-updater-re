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
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Picker("工作区", selection: $workspace) {
                        Text("实时").tag("live")
                        Text("历史记录").tag("history")
                    }.pickerStyle(.segmented).frame(width: 220)
                    Spacer()
                    Button { monitor.open() } label: {
                        Label("打开", systemImage: "folder").labelStyle(.titleAndIcon)
                    }.disabled(monitor.fileBusy)
                    exportMenu
                }
                if let error = monitor.errorMessage {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title3)
                        Text(error).textSelection(.enabled).font(.callout)
                        Spacer()
                        Button("关闭") { monitor.errorMessage = nil }
                    }.padding(12).background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                if monitor.fileBusy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在处理记录文件…").font(.callout)
                        Spacer()
                        Button("取消") { monitor.cancelFiles() }
                    }
                }
                if workspace == "live" {
                    readings
                    MonitorRecordingControls(monitor: monitor)
                } else {
                    historyView
                }
                if let path = monitor.displayedPath {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text").foregroundStyle(.secondary)
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .lineLimit(1).truncationMode(.middle).font(.callout)
                        Spacer()
                        Button { monitor.reveal() } label: {
                            Label("定位", systemImage: "arrow.right.circle").labelStyle(.iconOnly)
                        }
                    }.foregroundStyle(.secondary)
                }
                chartControls
                charts
                statistics
            }.padding(20)
        }
        .onChange(of: monitor.selectedRange) { selected in if selected { statisticsExpanded = true } }
    }

    private var readings: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 20) {
                reading("电压", monitor.latest?.voltage, "V", color: .blue)
                reading("电流", monitor.latest?.current, "A", color: .orange)
                reading("功率", monitor.latest?.power, "W", color: .green)
            }.opacity(monitor.state?.stale == true ? 0.4 : 1)
            DisclosureGroup("更多实时读数", isExpanded: $extraReadings) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 24) {
                        detailReading("内部温度", MonitorFormat.number(monitor.latest?.tempIn), "°C")
                        detailReading("外部温度", MonitorFormat.number(monitor.latest?.tempOut), "°C")
                    }
                    HStack(spacing: 24) {
                        detailReading("D+", MonitorFormat.number(monitor.latest?.dp), "V")
                        detailReading("D−", MonitorFormat.number(monitor.latest?.dn), "V")
                    }
                    HStack(spacing: 24) {
                        detailReading("累计容量", MonitorFormat.number(monitor.latest?.ah), "Ah")
                        detailReading("累计能量", MonitorFormat.number(monitor.latest?.wh), "Wh")
                    }
                    Divider()
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            Text("记录组").foregroundStyle(.secondary)
                            Text(monitor.latest?.group.map(String.init) ?? "—")
                        }
                        GridRow {
                            Text("设备记录").foregroundStyle(.secondary)
                            Text(deviceTime(monitor.latest?.recordSeconds))
                        }
                        GridRow {
                            Text("开机时长").foregroundStyle(.secondary)
                            Text(deviceTime(monitor.latest?.uptime))
                        }
                        GridRow {
                            Text("接收速率").foregroundStyle(.secondary)
                            Text("\(MonitorFormat.number(monitor.state?.receiveRate, digits: 1))/s")
                        }
                        GridRow {
                            Text("已记录").foregroundStyle(.secondary)
                            Text("\(monitor.state?.recordCount ?? 0)")
                        }
                    }.font(.callout.monospacedDigit())
                    if let invalid = monitor.state?.invalid, invalid > 0 {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text("已忽略 \(invalid) 个无效遥测包")
                        }.font(.callout).foregroundStyle(.orange).padding(.top, 4)
                    }
                }.padding(.top, 8)
            }.font(.callout).foregroundStyle(.secondary)
        }.padding(16).background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }
    private func deviceTime(_ seconds: Int?) -> String { seconds.map { MonitorFormat.elapsed(Double($0)) } ?? "—" }
    private func reading(_ title: String, _ value: Double?, _ unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(MonitorFormat.number(value)).font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(unit).font(.title3).foregroundStyle(.secondary)
            }.foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func detailReading(_ title: String, _ value: String, _ unit: String) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Text("\(value) \(unit)").monospacedDigit()
        }.font(.callout).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exportMenu: some View {
        Menu {
            Menu("全部记录") { exportItems(selection: false) }.disabled(monitor.displayedPath == nil || monitor.fileBusy)
            Menu("选中区间") { exportItems(selection: true) }.disabled(!monitor.selectedRange || monitor.fileBusy)
            Divider()
            Button("保存曲线 PNG…") { saveChart() }.disabled(monitor.points.isEmpty)
        } label: {
            Label("导出", systemImage: "square.and.arrow.up")
        }
    }
    @ViewBuilder private func exportItems(selection: Bool) -> some View {
        Button("官方兼容 CSV…") { monitor.export("csv", selection: selection) }
        Button("官方兼容 SQLite…") { monitor.export("official-sqlite", selection: selection) }
        Button("完整本地 SQLite…") { monitor.export("local-sqlite", selection: selection) }
    }

    private var chartControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                timeControls
                Spacer()
                navigationControls
            }
            Divider()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(MonitorChannel.allCases) { channel in
                    Toggle(channel.title, isOn: Binding(get: { monitor.channels.contains(channel) }, set: { enabled in
                        if enabled { monitor.channels.insert(channel) } else { monitor.channels.remove(channel) }
                    })).toggleStyle(.checkbox)
                }
            }.font(.callout)
        }
    }
    private var timeControls: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $monitor.follow) {
                Label("跟随最新", systemImage: "arrow.right.to.line")
            }.onChange(of: monitor.follow) { value in
                if value { monitor.selectedRange = false; monitor.refreshChart(stats: false) }
            }.disabled(!monitor.connected)
            Picker("窗口", selection: $monitor.windowSeconds) {
                Text("1 分钟").tag(60.0); Text("5 分钟").tag(300.0); Text("30 分钟").tag(1800.0)
            }.frame(width: 140)
        }.disabled(monitor.displayedPath == nil || monitor.querying)
    }
    private var navigationControls: some View {
        HStack(spacing: 8) {
            Button { monitor.refreshChart(stats: true, overview: true) } label: {
                Label("全程", systemImage: "arrow.up.left.and.arrow.down.right")
            }.help("全程概览")
            Divider().frame(height: 16)
            Button { monitor.zoom(0.5) } label: {
                Image(systemName: "plus.magnifyingglass")
            }.help("放大")
            Button { monitor.zoom(2) } label: {
                Image(systemName: "minus.magnifyingglass")
            }.help("缩小")
            Divider().frame(height: 16)
            Button { monitor.move(-1) } label: {
                Image(systemName: "chevron.left")
            }.help("向前移动")
            Button { monitor.move(1) } label: {
                Image(systemName: "chevron.right")
            }.help("向后移动")
            if monitor.querying { ProgressView().controlSize(.small) }
        }.disabled(monitor.displayedPath == nil || monitor.querying)
    }
    @ViewBuilder private var charts: some View {
        if !monitor.points.isEmpty {
            if monitor.channels.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.line.downtrend.xyaxis").font(.title).foregroundStyle(.secondary)
                    Text("请选择至少一个曲线通道").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).frame(height: 200)
            }
            ForEach(MonitorChannel.allCases.filter { monitor.channels.contains($0) }) { channel in
                MonitorChart(points: monitor.points, channel: channel,
                             start: monitor.query?.rangeStart ?? monitor.rangeStart,
                             end: monitor.query?.rangeEnd ?? monitor.rangeEnd,
                             selection: interval, onSelect: monitor.select)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "chart.xyaxis.line").font(.system(size: 44)).foregroundStyle(.secondary)
                Text(monitor.connected ? "等待遥测数据" : "连接 K2 或打开历史记录")
                    .font(.title3).foregroundStyle(.secondary)
                if !monitor.connected {
                    HStack(spacing: 12) {
                        Button { showConnection() } label: {
                            Label("设备连接", systemImage: "cable.connector")
                        }.buttonStyle(.borderedProminent)
                        Button { monitor.open() } label: {
                            Label("打开记录", systemImage: "folder")
                        }.disabled(monitor.fileBusy)
                    }
                }
            }.frame(maxWidth: .infinity).frame(height: 240)
        }
    }
    private var statistics: some View {
        DisclosureGroup("区间统计", isExpanded: $statisticsExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("起止秒数").font(.callout).foregroundStyle(.secondary)
                    TextField("开始", value: $monitor.rangeStart, format: .number).frame(width: 90)
                    Text("—").foregroundStyle(.secondary)
                    TextField("结束", value: $monitor.rangeEnd, format: .number).frame(width: 90)
                    Button { monitor.select(monitor.rangeStart, monitor.rangeEnd) } label: {
                        Label("计算", systemImage: "function")
                    }.disabled(monitor.querying || monitor.displayedPath == nil)
                    Spacer()
                }
                Text("也可直接拖选曲线；统计使用原始样本计算").font(.callout).foregroundStyle(.secondary)
                if let statistics = monitor.query?.statistics {
                    ScrollView(.horizontal) { MonitorStatisticsView(statistics: statistics) }
                }
            }.padding(.top, 10)
        }.font(.callout)
    }
    private var historyView: some View {
        GroupBox("本地记录") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("选择记录查看曲线和统计").foregroundStyle(.secondary).font(.callout)
                    Spacer()
                    Button { monitor.listRecords() } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }.disabled(monitor.fileBusy)
                }
                if monitor.connected {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("当前采集仍在运行。打开或导入可确认停止并保存；查看列表中的记录需要先断开采集")
                            .font(.callout).foregroundStyle(.orange)
                    }.padding(10).background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
                if monitor.records.isEmpty {
                    Text("默认目录暂无记录，其他位置的文件可通过打开或导入查看").foregroundStyle(.secondary).font(.callout)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(monitor.records) { record in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(URL(fileURLWithPath: record.path).lastPathComponent).lineLimit(1).font(.callout)
                                    HStack(spacing: 6) {
                                        Image(systemName: "chart.bar.doc.horizontal").font(.caption)
                                        Text("\(record.count) 样本")
                                        if record.unfinished {
                                            Image(systemName: "exclamationmark.circle.fill")
                                            Text("未正常结束")
                                        }
                                    }.foregroundStyle(record.unfinished ? .orange : .secondary).font(.caption)
                                }
                                Spacer()
                                Button { monitor.openSaved(record) } label: {
                                    Label("查看", systemImage: "chart.xyaxis.line")
                                }.disabled(monitor.connected || monitor.fileBusy)
                            }.padding(10).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }.frame(maxHeight: 200)
            }.padding(10)
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
