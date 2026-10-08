import SwiftUI
import K2Core

struct MonitorRecordingControls: View {
    @ObservedObject var monitor: MonitorStore
    @SceneStorage("monitorRecordingSettingsExpanded") private var settingsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if monitor.recording {
                    Button { monitor.pauseResume() } label: {
                        Label(monitor.paused ? "继续记录" : "暂停记录", systemImage: monitor.paused ? "play.circle" : "pause.circle")
                    }
                    Button { monitor.stopRecording() } label: {
                        Label("停止并保存", systemImage: "stop.circle")
                    }
                } else {
                    Button { monitor.startRecording() } label: {
                        Label("开始记录", systemImage: "record.circle")
                    }.buttonStyle(.borderedProminent).disabled(!monitor.connected)
                }
                if monitor.connected {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.doc.horizontal").foregroundStyle(.secondary).font(.callout)
                        Text("\(monitor.state?.recordCount ?? 0) 样本 · \(MonitorFormat.elapsed(monitor.state?.elapsed ?? 0))")
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                Menu {
                    Button { monitor.reveal() } label: {
                        Label("定位文件", systemImage: "arrow.right.circle")
                    }.disabled(monitor.displayedPath == nil)
                    Button { monitor.clearPreview() } label: {
                        Label("清除预览", systemImage: "trash")
                    }.disabled(!monitor.connected || monitor.recording || monitor.disconnecting)
                } label: {
                    Label("记录操作", systemImage: "ellipsis.circle")
                }
            }.disabled(monitor.controlPending || monitor.disconnecting)
            DisclosureGroup("记录设置", isExpanded: $settingsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("电脑采样上限").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Picker("电脑采样上限", selection: $monitor.rate) {
                            Text("1/s").tag(1); Text("10/s").tag(10); Text("100/s").tag(100); Text("全部接收").tag(0)
                        }.frame(maxWidth: 200).disabled(monitor.recording)
                    }
                    Divider()
                    Toggle("自动停止", isOn: $monitor.autoEnabled).disabled(monitor.recording).font(.callout)
                    HStack(spacing: 8) {
                        Picker("条件", selection: $monitor.autoKind) {
                            Text("|电流| (A)").tag("current"); Text("功率 (W)").tag("power")
                        }.labelsHidden().frame(width: 120)
                        Text("低于").foregroundStyle(.secondary)
                        TextField("阈值", value: $monitor.threshold, format: .number).frame(width: 64)
                        Text("连续").foregroundStyle(.secondary)
                        TextField("秒", value: $monitor.duration, format: .number).frame(width: 64)
                        Text("秒后停止").foregroundStyle(.secondary)
                    }.font(.callout).disabled(monitor.recording || !monitor.autoEnabled)
                    Text("采样设置只限制电脑记录速率。暂停时实时预览继续；数据按真实时间保存")
                        .font(.callout).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }.font(.callout)
        }.padding(14).background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }
}
