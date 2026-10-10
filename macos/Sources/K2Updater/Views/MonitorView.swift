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

    var body: some View {
        MonitorWorkspace(monitor: monitor, updater: updater, showConnection: showConnection,
                         workspace: $workspace, extraReadings: $extraReadings,
                         statisticsExpanded: $statisticsExpanded)
    }
}

/// The monitor page. Live and history share one arrangement: the command bar, the
/// voltage/current/power panel, a single line of chart controls and the charts
/// immediately beneath the panel.
struct MonitorWorkspace: View {
    @ObservedObject var monitor: MonitorStore
    @ObservedObject var updater: UpdaterStore
    let showConnection: () -> Void
    @Binding var workspace: String
    @Binding var extraReadings: Bool
    @Binding var statisticsExpanded: Bool

    @State private var showLocalRecordsCard = false
    @State private var showRecordingSettings = false
    @State private var contentWidth: CGFloat = 760

    private var interval: ClosedRange<Double>? {
        guard monitor.selectedRange, monitor.rangeStart.isFinite, monitor.rangeEnd.isFinite,
              monitor.rangeEnd >= monitor.rangeStart else { return nil }
        return monitor.rangeStart...monitor.rangeEnd
    }

    private var displayedChannels: [MonitorChannel] {
        MonitorChannel.allCases.filter { monitor.channels.contains($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                commandBar

                if workspace == "history" { localRecordsCard }

                if let error = monitor.errorMessage { errorBanner(error) }
                if monitor.fileBusy { fileBusyBanner }

                MonitorReadings(telemetry: monitor.telemetry, extraReadings: $extraReadings)

                chartCommandBar

                charts

                if let path = monitor.displayedPath { currentFile(path) }

                statistics
            }
            .padding(LayoutMetrics.pagePadding)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            max(0, min(geometry.size.width, 1180) - 2 * LayoutMetrics.pagePadding)
        } action: { width in
            if abs(contentWidth - width) > 1 { contentWidth = width }
        }
        .onChange(of: monitor.selectedRange) { selected in
            if selected { statisticsExpanded = true }
        }
        .onChange(of: workspace) { next in
            if next == "history" { monitor.listRecords() }
        }
    }

    // MARK: - Command bar

    /// Live/history toggle plus the recording, operation, settings and file
    /// commands, all on one line. Narrow windows use shorter labels so the row
    /// never wraps onto a second line.
    private var commandBar: some View {
        commandRow(compact: contentWidth < (monitor.connected ? 900 : 720))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .systemPanel()
    }

    private func commandRow(compact: Bool) -> some View {
        HStack(spacing: 10) {
            AnimatedSegmentedPicker(title: "采集视图", selection: $workspace,
                                    options: [("live", "实时"), ("history", "历史")])
            .frame(width: compact ? 128 : 146)

            if workspace == "live" { liveCommands(compact: compact) } else { historyCommands(compact: compact) }

            Spacer(minLength: 8)

            Button(compact ? "打开" : "打开记录") { monitor.open() }
                .fixedSize()
                .disabled(monitor.fileBusy)
                .help("打开官方 CSV、SQLite 或本地记录")

            exportMenu
        }
    }

    @ViewBuilder private func liveCommands(compact: Bool) -> some View {
        if monitor.recording {
            Button(monitor.paused ? "继续" : "暂停") { monitor.pauseResume() }
                .fixedSize()
            Button("停止") { monitor.stopRecording() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .fixedSize()
        } else {
            Button(compact ? "记录" : "开始记录") { monitor.startRecording() }
                .buttonStyle(.borderedProminent)
                .disabled(!monitor.connected)
                .fixedSize()
                .help("开始记录")
        }

        if monitor.connected && !compact {
            MonitorCaptureProgress(telemetry: monitor.telemetry)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 210, alignment: .leading)
        }

        Menu("操作") {
            Button("定位文件") { monitor.reveal() }
                .disabled(monitor.displayedPath == nil)
            Button("清除预览") { monitor.clearPreview() }
                .disabled(!monitor.connected || monitor.recording || monitor.disconnecting)
        }
        .fixedSize()

        Button(compact ? "设置" : "记录设置") { showRecordingSettings.toggle() }
            .fixedSize()
            .help("记录设置")
            .popover(isPresented: $showRecordingSettings, arrowEdge: .bottom) { recordingSettingsCard }
    }

    @ViewBuilder private func historyCommands(compact: Bool) -> some View {
        Button(compact ? "记录" : "本地记录") {
            showLocalRecordsCard.toggle()
        }
        .fixedSize()
        .help("列出最近记录，可选择查看或刷新")
    }

    // MARK: - Recording settings popover

    private var recordingSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("记录设置")
                .font(.headline)

            HStack(spacing: 10) {
                Text("采样上限")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .leading)
                Picker("", selection: $monitor.rate) {
                    Text("1/s").tag(1)
                    Text("10/s").tag(10)
                    Text("100/s").tag(100)
                    Text("全部").tag(0)
                }
                .labelsHidden()
                .frame(width: 130)
                .disabled(monitor.recording)
                Spacer(minLength: 0)
            }

            Toggle("低于阈值自动停止", isOn: $monitor.autoEnabled)
                .disabled(monitor.recording)

            HStack(spacing: 8) {
                Picker("", selection: $monitor.autoKind) {
                    Text("|电流|").tag("current")
                    Text("功率").tag("power")
                }
                .labelsHidden()
                .frame(width: 88)

                Text("低于").foregroundStyle(.secondary)
                TextField("", value: $monitor.threshold, format: .number)
                    .frame(width: 62)
                Text("连续").foregroundStyle(.secondary)
                TextField("", value: $monitor.duration, format: .number)
                    .frame(width: 52)
                Text("秒")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .disabled(monitor.recording || !monitor.autoEnabled)

            Text("采样上限在开始记录后不可更改。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: - Local records card

    @ViewBuilder private var localRecordsCard: some View {
        if showLocalRecordsCard {
            LocalRecordsCard(
                records: monitor.records,
                busy: monitor.fileBusy,
                connected: monitor.connected,
                onRefresh: { monitor.listRecords() },
                onOpen: { monitor.openSaved($0) },
                onClose: { showLocalRecordsCard = false }
            )
        }
    }

    // MARK: - Banners

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 12) {
            Text("⚠")
                .font(.title3)
                .foregroundStyle(.red)
            Text(error)
                .font(.callout)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button("关闭") { monitor.errorMessage = nil }
        }
        .padding(14)
        .background(Color.red.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var fileBusyBanner: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("正在处理文件")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("取消") { monitor.cancelFiles() }
        }
    }

    private func currentFile(_ path: String) -> some View {
        HStack(spacing: 10) {
            Text(URL(fileURLWithPath: path).lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("定位") { monitor.reveal() }
                .font(.caption)
                .buttonStyle(.borderless)
        }
    }

    // MARK: - Chart controls (single line)

    private var chartCommandBar: some View {
        HStack(spacing: 12) {
            chartControls
                .disabled(monitor.displayedPath == nil)

            MonitorQueryProgress(activity: monitor.queryActivity)

            Spacer(minLength: 0)

            Text(shortRange(monitor.rangeStart, monitor.rangeEnd))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                // Kept at its ideal width so the channel selector drops a tier
                // instead of the range collapsing to an ellipsis.
                .fixedSize()
                .help("当前查看范围")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .systemPanel()
    }

    /// Compact "start – end" readout so the chart control line never needs a
    /// second row to show the viewing range.
    private func shortRange(_ start: Double, _ end: Double) -> String {
        func format(_ value: Double) -> String {
            guard value.isFinite, value >= 0 else { return "—" }
            if value >= 3600 { return String(format: "%.1fh", value / 3600) }
            if value >= 60 {
                return String(format: "%d:%04.1f", Int(value / 60), value.truncatingRemainder(dividingBy: 60))
            }
            return String(format: "%.1fs", value)
        }
        return "\(format(start)) – \(format(end))"
    }

    private var chartControls: some View {
        HStack(spacing: 10) {
            Toggle("跟随", isOn: $monitor.follow)
                .toggleStyle(.checkbox)
                .disabled(!monitor.connected)
                .onChange(of: monitor.follow) { value in
                    if value {
                        monitor.selectedRange = false
                        monitor.refreshChart(stats: false)
                    }
                }
                .help("自动跟随最新数据")

            Picker("", selection: $monitor.windowSeconds) {
                Text("1 分钟").tag(60.0)
                Text("5 分钟").tag(300.0)
                Text("30 分钟").tag(1800.0)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 104)
            .help("时间窗口")

            Button("全程") { monitor.refreshChart(stats: true, overview: true) }
                .help("全程概览")

            Divider().frame(height: 18)

            Button("−") { monitor.zoom(2) }.help("缩小")
            Button("+") { monitor.zoom(0.5) }.help("放大")

            Divider().frame(height: 18)

            Button("←") { monitor.move(-1) }.help("前移")
            Button("→") { monitor.move(1) }.help("后移")

            Divider().frame(height: 18)

            channelSelector
        }
        .buttonStyle(.borderless)
        .font(.callout)
    }

    /// Channel selectors stay on the one control line: all seven when there is
    /// room, then the three primary channels plus a menu, then the menu alone.
    private var channelSelector: some View {
        Group {
            if contentWidth >= 940 {
                HStack(spacing: 10) {
                    ForEach(MonitorChannel.allCases) { channel in channelToggle(channel) }
                }
            } else if contentWidth >= 780 {
                HStack(spacing: 10) {
                    ForEach([MonitorChannel.voltage, .current, .power]) { channel in channelToggle(channel) }
                    allChannelsMenu
                }
            } else {
                allChannelsMenu
            }
        }
    }

    private func channelToggle(_ channel: MonitorChannel) -> some View {
        Toggle(channel.title, isOn: channelBinding(channel))
            .toggleStyle(.checkbox)
            .fixedSize()
    }

    private var allChannelsMenu: some View {
        Menu("通道") {
            ForEach(MonitorChannel.allCases) { channel in
                Toggle(channel.title, isOn: channelBinding(channel))
            }
        }
        .fixedSize()
        .help("选择曲线通道")
    }

    private func channelBinding(_ channel: MonitorChannel) -> Binding<Bool> {
        Binding(
            get: { monitor.channels.contains(channel) },
            set: { enabled in
                if enabled { monitor.channels.insert(channel) } else { monitor.channels.remove(channel) }
            }
        )
    }

    // MARK: - Charts

    @ViewBuilder private var charts: some View {
        if !monitor.points.isEmpty {
            if monitor.channels.isEmpty {
                emptyChartPanel(message: "请选择至少一个曲线通道", height: 180) { EmptyView() }
            } else {
                VStack(spacing: 12) {
                    ForEach(displayedChannels) { channel in
                        MonitorChart(
                            points: monitor.points,
                            channel: channel,
                            start: monitor.query?.rangeStart ?? monitor.rangeStart,
                            end: monitor.query?.rangeEnd ?? monitor.rangeEnd,
                            selection: interval,
                            onSelect: monitor.select
                        )
                    }
                }
            }
        } else {
            emptyChartPanel(message: monitor.connected ? "等待遥测数据" : "连接 K2 或打开历史记录",
                            height: 220) {
                if !monitor.connected {
                    HStack(spacing: 12) {
                        Button("设备连接") { showConnection() }
                            .buttonStyle(.borderedProminent)
                        Button("打开记录") { monitor.open() }
                            .disabled(monitor.fileBusy)
                    }
                }
            }
        }
    }

    private func emptyChartPanel<Actions: View>(message: String, height: CGFloat,
                                                @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 14) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            actions()
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .systemPanel()
    }

    // MARK: - Statistics

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
                    Button("计算") { monitor.select(monitor.rangeStart, monitor.rangeEnd) }
                        .disabled(monitor.displayedPath == nil)
                    Spacer(minLength: 0)
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

    // MARK: - Helpers

    private func deviceTime(_ seconds: Int?) -> String {
        seconds.map { MonitorFormat.elapsed(Double($0)) } ?? "—"
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
        .fixedSize()
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
            channels: displayedChannels,
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
