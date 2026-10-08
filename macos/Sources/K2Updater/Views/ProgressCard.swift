import SwiftUI

struct ProgressCard: View {
    @ObservedObject var store: UpdaterStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if store.isBusy { ProgressView().controlSize(.small) }
                else if store.successful { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                else if store.errorMessage != nil { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red) }
                Text(store.status).fontWeight(.medium).textSelection(.enabled)
                Spacer()
                if store.isBusy && store.total > 0 { Text("\(Int(store.progress * 100))%").monospacedDigit() }
            }
            if store.isBusy {
                if store.total > 0 { ProgressView(value: store.progress) }
                else { ProgressView().progressViewStyle(.linear) }
            }
            if let error = store.errorMessage {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            } else if store.isBusy && store.operation?.isWrite == true {
                Text("备份校验通过后才开始擦写。请保持设备连接，等待任务完成。").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("备份与日志保存在本机，完成后可直接打开文件夹。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}
