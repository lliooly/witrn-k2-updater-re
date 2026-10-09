import SwiftUI
import K2Core

struct MonitorRecordingControls: View {
    @ObservedObject var monitor: MonitorStore
    @SceneStorage("monitorRecordingSettingsExpanded") private var settingsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 记录控制 - 极简
            HStack(spacing: 12) {
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
                    Text("\(monitor.state?.recordCount ?? 0) 样本")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(MonitorFormat.elapsed(monitor.state?.elapsed ?? 0))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu("操作") {
                    Button("定位文件") { monitor.reveal() }
                        .disabled(monitor.displayedPath == nil)
                    Button("清除预览") { monitor.clearPreview() }
                        .disabled(!monitor.connected || monitor.recording || monitor.disconnecting)
                }
            }
            .disabled(monitor.controlPending || monitor.disconnecting)

            // 设置 - 折叠
            if settingsExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 14) {
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

            // 折叠按钮
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    settingsExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(settingsExpanded ? "收起设置" : "记录设置")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Image(systemName: settingsExpanded ? "chevron.up" : "chevron.down")
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
}
