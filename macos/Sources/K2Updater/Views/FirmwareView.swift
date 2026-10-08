import SwiftUI

struct FirmwareView: View {
    @ObservedObject var store: UpdaterStore
    let showConnection: () -> Void
    @State private var confirmUpgrade = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                step("1", "确认设备", complete: store.canUseResources)
                HStack {
                    Text(store.monitorConnected ? "采集仍在运行，请先断开并重新进入 DFU。" : "在右侧连接栏进入 DFU 维护，读取设备信息。")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("设备连接") { showConnection() }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                step("2", "选择固件", complete: store.firmware != nil && !store.isDemoFirmware)
                FirmwareCard(store: store)
                HStack(spacing: 24) {
                    version("当前版本", store.identity?.currentVersion ?? "未读取")
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    version("目标版本", store.firmware?.version ?? "未选择")
                    Spacer()
                }.padding(12)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                step("3", "备份并升级", complete: false)
                Text("先完成双遍备份，再写入并读回校验。请保持设备连接。")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("仅备份固件") { store.backup() }.disabled(!store.canUseResources)
                    Spacer()
                    Button("备份并升级") { confirmUpgrade = true }.buttonStyle(.borderedProminent)
                        .controlSize(.large).disabled(!store.canUpgrade)
                }
                if !store.canUseResources { ResourceAvailabilityHint(store: store) }
            }
        }
        .alert("备份并升级到 \(store.firmware?.version ?? "")？", isPresented: $confirmUpgrade) {
            Button("取消", role: .cancel) {}
            Button("备份并升级") { store.upgrade() }
        } message: {
            Text("先完整读取两遍并核对备份，再擦除应用区并写入所选固件。当前 \(store.identity?.currentVersion ?? "未知") → 目标 \(store.firmware?.version ?? "未知")。升级期间请保持连接。")
        }
    }

    private func step(_ number: String, _ title: String, complete: Bool) -> some View {
        HStack(spacing: 10) {
            Text(complete ? "✓" : number).font(.callout.weight(.semibold))
                .frame(width: 26, height: 26).background(.quaternary, in: Circle())
                .foregroundStyle(complete ? Color.green : Color.primary)
            Text(title).font(.headline)
        }
    }
    private func version(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold))
        }
    }
}

struct ResourceAvailabilityHint: View {
    @ObservedObject var store: UpdaterStore
    var body: some View {
        Text(store.monitorConnected ? "设备维护不可用：请先在连接栏断开采集，再进入 DFU 并读取设备信息。"
             : store.isBusy ? "设备任务正在进行，完成后可继续操作。"
             : "设备操作需要在右侧连接栏选择 DFU 维护、确认接入方式并读取设备信息。离线编辑和保存无需连接。")
            .font(.caption).foregroundStyle(.secondary)
    }
}
