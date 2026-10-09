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
    @State private var showLocalRecordsCard = false
    private var interval: ClosedRange<Double>? {
        guard monitor.selectedRange, monitor.rangeStart.isFinite, monitor.rangeEnd.isFinite,
              monitor.rangeEnd >= monitor.rangeStart else { return nil }
        return monitor.rangeStart...monitor.rangeEnd
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 工作区切换 + 操作按钮 (单行)
                HStack(spacing: 16) {
                    Picker("", selection: $workspace) {
                        Text("实时").tag("live")
                        Text("历史").tag("history")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)

                    if workspace == "live" {
                        // Real-time controls on same line
                        HStack(spacing: 8) {
                            if monitor.recording {
                                Button(monitor.paused ? "继续" : "暂停") {
                                    monitor.pauseResume()
                                }
                                .frame(width: 70)

                                Button("停止") {
                                    monitor.stopRecording()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red.opacity(0.8))
                            } else {
                                Button("开始记录") {
                                    monitor.startRecording()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!monitor.connected)
                            }

                            if monitor.connected {
                                Text("\(monitor.state?.recordCount ?? 0) 样本 · \(MonitorFormat.elapsed(monitor.state?.elapsed ?? 0))")
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        // History page: Local Records button
                        Button {
                            showLocalRecordsCard.toggle()
                        } label: {
                            Label("本地记录", systemImage: "folder.fill")
                        }
                        .popover(isPresented: $showLocalRecordsCard, arrowEdge: .top) {
                            localRecordsPopover
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button("打开") { monitor.open() }
                            .disabled(monitor.fileBusy)
                        exportMenu
                    }
                }

                // 错误提示
                if let error = monitor.errorMessage {
                    HStack(spacing: 12) {
                        Text("⚠")
                            .font(.title3)
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.callout)
                            .textSelection(.enabled)
                        Spacer()
                        Button("关闭") { monitor.errorMessage = nil }
                            .buttonStyle(.borderless)
                    }
                    .padding(14)
                    .background(Color.red.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // 文件处理状态
                if monitor.fileBusy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在处理文件")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("取消") { monitor.cancelFiles() }
                    }
                }

                // 主内容 - Real-time
                if workspace == "live" {
                    readings
                    recordingControls
                } else {
                    // History page content
                    historyHeaderInfo
                }

                // 当前文件
                if let path = monitor.displayedPath {
                    HStack(spacing: 10) {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("定位") { monitor.reveal() }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                }

                Divider()

                // 图表控制 (单行布局)
                consolidatedChartControls

                // 图表显示
                charts

                // 统计信息
                statistics
            }
            .padding(24)
        }
        .onChange(of: monitor.selectedRange) { selected in
            if selected { statisticsExpanded = true }
        }
    }

    // MARK: - Readings Display (Liquid Glass)
    private var readings: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 0) {
                reading("电压", monitor.latest?.voltage, "V")
                Divider().frame(height: 60).padding(.horizontal, 24)
                reading("电流", monitor.latest?.current, "A")
                Divider().frame(height: 60).padding(.horizontal, 24)
                reading("功率", monitor.latest?.power, "W")
            }
            .opacity(monitor.state?.stale == true ? 0.35 : 1)
            .padding(.vertical, 8)

            if extraReadings {
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 32) {
                        detailReading("内部温度", MonitorFormat.number(monitor.latest?.tempIn), "°C")
                        detailReading("外部温度", MonitorFormat.number(monitor.latest?.tempOut), "°C")
                        Spacer()
                    }
                    HStack(spacing: 32) {
                        detailReading("D+", MonitorFormat.number(monitor.latest?.dp), "V")
                        detailReading("D−", MonitorFormat.number(monitor.latest?.dn), "V")
                        detailReading("累计", "\(MonitorFormat.number(monitor.latest?.ah)) Ah", "· \(MonitorFormat.number(monitor.latest?.wh)) Wh")
                        Spacer()
                    }
                    HStack(spacing: 32) {
                        detailReading("记录组", monitor.latest?.group.map(String.init) ?? "—", "")
                        detailReading("设备记录", deviceTime(monitor.latest?.recordSeconds), "")
                        detailReading("接收", "\(MonitorFormat.number(monitor.state?.receiveRate, digits: 1))/s", "· \(monitor.state?.recordCount ?? 0) 样本")
                        Spacer()
                    }
                    if let invalid = monitor.state?.invalid, invalid > 0 {
                        Text("⚠ 已忽略 \(invalid) 个无效遥测包")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }.font(.callout.monospacedDigit())
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    extraReadings.toggle()
                }
            } label: {
                HStack {
                    Text(extraReadings ? "收起详细信息" : "显示详细信息")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Image(systemName: extraReadings ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Menu("操作") {
                    Button("定位文件") { monitor.reveal() }
                        .disabled(monitor.displayedPath == nil)
                    Button("清除预览") { monitor.clearPreview() }
                        .disabled(!monitor.connected || monitor.recording || monitor.disconnecting)
                }
                Spacer()
                Menu("记录设置") {
                    HStack {
                        Text("采样上限")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Picker("", selection: $monitor.rate) {
                            Text("1/s").tag(1)
                            Text("10/s").tag(10)
                            Text("100/s").tag(100)
                            Text("全部").tag(0)
                        }
                        .frame(width: 140)
                        .disabled(monitor.recording)
                    }

                    HStack {
                        Toggle("自动停止", isOn: $monitor.autoEnabled)
                            .frame(width: 220)
                            .disabled(monitor.recording)
                    }

                    HStack(spacing: 10) {
                        Picker("", selection: $monitor.autoKind) {
                            Text("|电流|").tag("current")
                            Text("功率").tag("power")
                        }
                        .labelsHidden()
                        .frame(width: 90)

                        Text("低于")
                            .foregroundStyle(.secondary)
                        TextField("", value: $monitor.threshold, format: .number)
                            .frame(width: 60)

                        Text("连续")
                            .foregroundStyle(.secondary)
                        TextField("", value: $monitor.duration, format: .number)
                            .frame(width: 60)

                        Text("秒后停止")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .disabled(monitor.recording || !monitor.autoEnabled)
                }
            }
            .disabled(monitor.controlPending || monitor.disconnecting)
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var historyHeaderInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                Text("选择本地记录查看曲线和统计")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if monitor.connected {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("当前采集仍在运行。打开或导入可确认停止并保存；查看列表中的记录需要先断开采集")
                        .font(.callout).foregroundStyle(.orange)
                }.padding(10).background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var localRecordsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("本地记录")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button { monitor.listRecords() } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(monitor.fileBusy)
                .buttonStyle(.borderless)
            }

            if monitor.records.isEmpty {
                Text("默认目录暂无记录，其他位置的文件可通过打开或导入查看")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(monitor.records) { record in
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(URL(fileURLWithPath: record.path).lastPathComponent)
                                        .lineLimit(1)
                                        .font(.callout)
                                    HStack(spacing: 6) {
                                        Image(systemName: "chart.bar.doc.horizontal")
                                            .font(.caption)
                                        Text("\(record.count) 样本")
                                        if record.unfinished {
                                            Image(systemName: "exclamationmark.circle.fill")
                                            Text("未正常结束")
                                        }
                                    }
                                    .foregroundStyle(record.unfinished ? .orange : .secondary)
                                    .font(.caption)
                                }
                                Spacer()
                                Button { monitor.openSaved(record) } label: {
                                    Label("查看", systemImage: "chart.xyaxis.line")
                                }
                                .disabled(monitor.connected || monitor.fileBusy)
                            }
                            .padding(10)
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .padding(16)
        .frame(width: 400)
    }

    // MARK: - Consolidated Chart Controls (Single Line)
    private var consolidatedChartControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Time and navigation controls in one line
            HStack(spacing: 12) {
                Toggle("跟随", isOn: $monitor.follow)
                    .onChange(of: monitor.follow) { value in
                        if value {
                            monitor.selectedRange = false
                            monitor.refreshChart(stats: false)
                        }
                    }
                    .disabled(!monitor.connected)
                    .frame(width: 90)

                Picker("窗口", selection: $monitor.windowSeconds) {
                    Text("1 分钟").tag(60.0)
                    Text("5 分钟").tag(300.0)
                    Text("30 分钟").tag(1800.0)
                }
                .frame(width: 120)

                Divider().frame(height: 20)

                Button("全程") {
                    monitor.refreshChart(stats: true, overview: true)
                }
                .help("全程概览")

                Divider().frame(height: 16).padding(.horizontal, 4)

                HStack(spacing: 4) {
                    Button("−") { monitor.zoom(2) }.help("缩小")
                    Button("+") { monitor.zoom(0.5) }.help("放大")
                }

                Divider().frame(height: 16).padding(.horizontal, 4)

                HStack(spacing: 4) {
                    Button("←") { monitor.move(-1) }.help("前移")
                    Button("→") { monitor.move(1) }.help("后移")
                }

                if monitor.querying {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 4)
                }

                Spacer()
            }
            .font(.title3)
            .buttonStyle(.borderless)
            .disabled(monitor.displayedPath == nil || monitor.querying)

            Divider()

            // Channel selection - compact grid
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 85), spacing: 16)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(MonitorChannel.allCases) { channel in
                    Toggle(channel.title, isOn: Binding(
                        get: { monitor.channels.contains(channel) },
                        set: { enabled in
                            if enabled {
                                monitor.channels.insert(channel)
                            } else {
                                monitor.channels.remove(channel)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.callout)
                }
            }
        }
    }

    @ViewBuilder private var charts: some View {
        if !monitor.points.isEmpty {
            if monitor.channels.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.line.downtrend.xyaxis")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("请选择至少一个曲线通道")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            }
            ForEach(MonitorChannel.allCases.filter { monitor.channels.contains($0) }) { channel in
                MonitorChart(
                    points: monitor.points,
                    channel: channel,
                    start: monitor.query?.rangeStart ?? monitor.rangeStart,
                    end: monitor.query?.rangeEnd ?? monitor.rangeEnd,
                    selection: interval,
                    onSelect: monitor.select
                )
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(monitor.connected ? "等待遥测数据" : "连接 K2 或打开历史记录")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                if !monitor.connected {
                    HStack(spacing: 12) {
                        Button { showConnection() } label: {
                            Label("设备连接", systemImage: "cable.connector")
                        }
                        .buttonStyle(.borderedProminent)
                        Button { monitor.open() } label: {
                            Label("打开记录", systemImage: "folder")
                        }
                        .disabled(monitor.fileBusy)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 240)
        }
    }

    private var statistics: some View {
        DisclosureGroup("区间统计", isExpanded: $statisticsExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("起止秒数")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField("开始", value: $monitor.rangeStart, format: .number)
                        .frame(width: 90)
                    Text("—")
                        .foregroundStyle(.secondary)
                    TextField("结束", value: $monitor.rangeEnd, format: .number)
                        .frame(width: 90)
                    Button { monitor.select(monitor.rangeStart, monitor.rangeEnd) } label: {
                        Label("计算", systemImage: "function")
                    }
                    .disabled(monitor.querying || monitor.displayedPath == nil)
                    Spacer()
                }
                Text("也可直接拖选曲线；统计使用原始样本计算")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let statistics = monitor.query?.statistics {
                    ScrollView(.horizontal) {
                        MonitorStatisticsView(statistics: statistics)
                    }
                }
            }
            .padding(.top, 10)
        }
        .font(.callout)
    }

    // MARK: - Helper Functions
    private func deviceTime(_ seconds: Int?) -> String {
        seconds.map { MonitorFormat.elapsed(Double($0)) } ?? "—"
    }

    private func reading(_ title: String, _ value: Double?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(MonitorFormat.number(value))
                    .font(.system(size: 42, weight: .regular, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailReading(_ title: String, _ value: String, _ suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value + (suffix.isEmpty ? "" : " " + suffix))
                .font(.callout.monospacedDigit())
        }
    }

    private var exportMenu: some View {
        Menu("导出") {
            Menu("全部记录") { exportItems(selection: false) }
                .disabled(monitor.displayedPath == nil || monitor.fileBusy)
            Menu("选中区间") { exportItems(selection: true) }
                .disabled(!monitor.selectedRange || monitor.fileBusy)
            Divider()
            Button("保存曲线 PNG") { saveChart() }
                .disabled(monitor.points.isEmpty)
        }
    }

    @ViewBuilder private func exportItems(selection: Bool) -> some View {
        Button("官方兼容 CSV…") { monitor.export("csv", selection: selection) }
        Button("官方兼容 SQLite…") { monitor.export("official-sqlite", selection: selection) }
        Button("完整本地 SQLite…") { monitor.export("local-sqlite", selection: selection) }
    }

    @MainActor private func saveChart() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "K2-chart.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let renderer = ImageRenderer(content: MonitorPlotExport(
            points: monitor.points,
            channels: MonitorChannel.allCases.filter { monitor.channels.contains($0) },
            start: monitor.query?.rangeStart ?? 0,
            end: monitor.query?.rangeEnd ?? 1
        ))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            monitor.errorMessage = "曲线图片生成失败"
            return
        }
        do { try png.write(to: url, options: .atomic) }
        catch { monitor.errorMessage = error.localizedDescription }
    }
}
