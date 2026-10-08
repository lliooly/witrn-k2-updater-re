import SwiftUI
import K2Core

struct MonitorRecordingControls: View {
    @ObservedObject var monitor: MonitorStore
    @SceneStorage("monitorRecordingSettingsExpanded") private var settingsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if monitor.recording {
                    Button(monitor.paused ? "继续记录" : "暂停记录") { monitor.pauseResume() }
                    Button("停止并保存") { monitor.stopRecording() }
                } else {
                    Button("开始记录…") { monitor.startRecording() }.buttonStyle(.borderedProminent).disabled(!monitor.connected)
                }
                if monitor.connected {
                    Text("\(monitor.state?.recordCount ?? 0) 样本 · \(MonitorFormat.elapsed(monitor.state?.elapsed ?? 0))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Menu("记录操作") {
                    Button("定位文件") { monitor.reveal() }.disabled(monitor.displayedPath == nil)
                    Button("清除预览") { monitor.clearPreview() }.disabled(!monitor.connected || monitor.recording || monitor.disconnecting)
                }.fixedSize()
            }.disabled(monitor.controlPending || monitor.disconnecting)
            DisclosureGroup("记录设置", isExpanded: $settingsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("电脑采样上限", selection: $monitor.rate) {
                        Text("1/s").tag(1); Text("10/s").tag(10); Text("100/s").tag(100); Text("全部接收").tag(0)
                    }.frame(maxWidth: 260).disabled(monitor.recording)
                    Toggle("自动停止", isOn: $monitor.autoEnabled).disabled(monitor.recording)
                    HStack {
                        Picker("条件", selection: $monitor.autoKind) {
                            Text("|电流| (A)").tag("current"); Text("功率 (W)").tag("power")
                        }.labelsHidden().frame(width: 115)
                        Text("低于")
                        TextField("阈值", value: $monitor.threshold, format: .number).frame(width: 60)
                        Text("连续")
                        TextField("秒", value: $monitor.duration, format: .number).frame(width: 60)
                        Text("秒后停止")
                    }.font(.callout).disabled(monitor.recording || !monitor.autoEnabled)
                    Text("采样设置只限制电脑记录速率。暂停时实时预览继续；数据按真实时间保存。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }.font(.callout)
        }
    }
}
