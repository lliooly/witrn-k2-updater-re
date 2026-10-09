import SwiftUI

struct FirmwareView: View {
    @ObservedObject var store: UpdaterStore
    let showConnection: () -> Void
    @State private var confirmUpgrade = false

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // 步骤 1
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    stepIndicator("1", complete: store.canUseResources)
                    Text("确认设备")
                        .font(.title3)
                }

                if store.monitorConnected {
                    Text("⚠ 采集仍在运行，请先断开并重新进入 DFU")
                        .font(.callout)
                        .foregroundStyle(.red)
                } else {
                    HStack {
                        Text("在右侧连接栏进入 DFU 维护，读取设备信息")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("连接") { showConnection() }
                    }
                }
            }

            Divider()

            // 步骤 2
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    stepIndicator("2", complete: store.firmware != nil && !store.isDemoFirmware)
                    Text("选择固件")
                        .font(.title3)
                }

                FirmwareCard(store: store)

                // 版本对比
                HStack(spacing: 24) {
                    versionDisplay("当前版本", store.identity?.currentVersion ?? "未读取")
                    Text("→")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    versionDisplay("目标版本", store.firmware?.version ?? "未选择")
                    Spacer()
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Divider()

            // 步骤 3
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    stepIndicator("3", complete: false)
                    Text("备份并升级")
                        .font(.title3)
                }

                Text("⚠ 先完成双遍备份，再写入并读回校验。请保持设备连接")
                    .font(.callout)
                    .foregroundStyle(.red)

                HStack(spacing: 12) {
                    Button("仅备份") { store.backup() }
                        .disabled(!store.canUseResources)
                    Spacer()
                    Button("备份并升级") { confirmUpgrade = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!store.canUpgrade)
                }

                if !store.canUseResources {
                    ResourceAvailabilityHint(store: store)
                }
            }
        }
        .alert("备份并升级到 \(store.firmware?.version ?? "")？", isPresented: $confirmUpgrade) {
            Button("取消", role: .cancel) {}
            Button("确认升级") { store.upgrade() }
        } message: {
            Text("当前 \(store.identity?.currentVersion ?? "未知") → 目标 \(store.firmware?.version ?? "未知")。升级期间请保持连接")
        }
    }

    private func stepIndicator(_ number: String, complete: Bool) -> some View {
        Text(complete ? "✓" : number)
            .font(.callout.weight(.medium))
            .foregroundStyle(complete ? .green : .primary)
            .frame(width: 28, height: 28)
            .background(complete ? Color.green.opacity(0.15) : Color(white: 0.5, opacity: 0.12))
            .clipShape(Circle())
    }

    private func versionDisplay(_ label: String, _ version: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(version)
                .font(.title3)
                .fontWeight(.medium)
        }
    }
}

struct ResourceAvailabilityHint: View {
    @ObservedObject var store: UpdaterStore
    var body: some View {
        Text("⚠ " + (store.monitorConnected ? "设备维护不可用：请先在连接栏断开采集，再进入 DFU 并读取设备信息"
             : store.isBusy ? "设备任务正在进行，完成后可继续操作"
             : "设备操作需要在右侧连接栏选择 DFU 维护、确认接入方式并读取设备信息"))
            .font(.callout)
            .foregroundStyle(.red)
    }
}
