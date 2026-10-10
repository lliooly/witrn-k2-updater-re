import SwiftUI
import K2Core

/// The card revealed by the history page's "本地记录" button: recent recordings
/// plus a refresh entry point.
struct LocalRecordsCard: View {
    let records: [MonitorRecord]
    let busy: Bool
    let connected: Bool
    let onRefresh: () -> Void
    let onOpen: (MonitorRecord) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("最近记录")
                    .font(.headline)
                Spacer(minLength: 8)
                Button("刷新", action: onRefresh)
                    .disabled(busy)
                    .help("重新读取默认记录目录")
                Button("收起", action: onClose)
                    .help("收起记录列表")
            }

            if records.isEmpty {
                Text("默认目录暂无记录，其他位置的文件可通过打开或导入查看")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(records) { record in
                            row(record)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(14)
        .systemPanel()
    }

    private func row(_ record: MonitorRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(URL(fileURLWithPath: record.path).lastPathComponent)
                    .lineLimit(1)
                    .font(.callout)
                HStack(spacing: 6) {
                    Text("\(record.count) 样本")
                    if record.unfinished {
                        Text("⚠ 未正常结束")
                    }
                }
                .foregroundStyle(record.unfinished ? .orange : .secondary)
                .font(.caption)
            }

            Spacer(minLength: 8)

            Button("查看") { onOpen(record) }
                .disabled(connected || busy)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.quaternary.opacity(0.3))
        }
    }
}
