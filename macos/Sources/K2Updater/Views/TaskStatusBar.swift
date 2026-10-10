import SwiftUI
import K2Core

struct TaskStatusBar: View {
    @ObservedObject var store: UpdaterStore
    @ObservedObject var monitor: MonitorStore
    var firmwareOnly = false
    @State private var showError = false

    var body: some View {
        Group {
            if firmwareOnly { firmwareStatus }
            else { taskStatus }
        }
    }

    private var firmwareStatus: some View {
        HStack(spacing: 10) {
            if store.errorMessage != nil {
                Label("操作未完成", systemImage: "exclamationmark.circle").foregroundStyle(.red)
            } else if store.identity?.confirmedK2 == true && store.dfuConfirmed {
                Label("连接成功", systemImage: "checkmark.circle").foregroundStyle(.green)
            } else if store.firmwareWizardStep == 3 && store.successful {
                Label("升级完成 · 请重新上电", systemImage: "checkmark.circle").foregroundStyle(.green)
            } else {
                let summary = ConnectionPresentation.current(updater: store, monitor: monitor)
                Label(summary.title, systemImage: summary.symbol).foregroundStyle(summary.color)
            }
            Spacer()
            Button("日志") { store.showLog() }.disabled(store.tracePath == nil)
        }
        .font(.caption).padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var taskStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if store.isBusy {
                    ProgressView().controlSize(.small)
                    Text(store.status).lineLimit(1)
                    if store.total > 0 { Text("\(Int(store.progress * 100))%").monospacedDigit() }
                    Spacer()
                    if store.canCancel { Button("取消只读操作") { store.cancel() } }
                } else if monitor.fileBusy {
                    ProgressView().controlSize(.small)
                    Text("正在处理记录文件…")
                    Spacer()
                    Button("取消文件操作") { monitor.cancelFiles() }
                } else if store.errorMessage != nil || monitor.errorMessage != nil {
                    Label("操作未完成", systemImage: "exclamationmark.circle").foregroundStyle(.red)
                    Text(store.errorMessage ?? monitor.errorMessage ?? "").lineLimit(1).textSelection(.enabled)
                    Spacer()
                    Button(showError ? "收起详情" : "错误详情") { showError.toggle() }
                } else if monitor.connected {
                    let summary = ConnectionPresentation.current(updater: store, monitor: monitor)
                    Label(summary.title, systemImage: summary.symbol).foregroundStyle(summary.color)
                    Text(monitor.message).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    MonitorCaptureProgress(telemetry: monitor.telemetry, showsElapsed: false)
                } else {
                    Label(store.status, systemImage: store.successful ? "checkmark.circle" : "info.circle")
                        .foregroundStyle(store.successful ? Color.green : Color.secondary).lineLimit(1)
                    Spacer()
                }
                if store.backupPath != nil { Button("备份文件夹") { store.showBackup() } }
                if store.tracePath != nil { Button("日志") { store.showLog() } }
            }
            if store.isBusy && store.total > 0 { ProgressView(value: store.progress) }
            if showError, let error = store.errorMessage ?? monitor.errorMessage {
                ScrollView { Text(error).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 90)
            }
            if store.isBusy && store.operation?.isWrite == true {
                Text("正在备份、写入或校验，请保持连接并等待任务完成。").foregroundStyle(.secondary)
            }
        }.font(.caption).padding(.horizontal, 16).padding(.vertical, 10)
    }
}
