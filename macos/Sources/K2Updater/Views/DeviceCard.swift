import SwiftUI

struct DeviceCard: View {
    @ObservedObject var store: UpdaterStore

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("设备", systemImage: "cable.connector").font(.headline)
                    Spacer()
                    Button("刷新设备") { store.refreshDevices() }.disabled(store.isBusy)
                }
                if store.devices.isEmpty {
                    Text("未发现设备").font(.title3)
                    Text("按住减号键，从 CC1/HID 口使用数据线连接 Mac。").foregroundStyle(.secondary)
                } else {
                    Picker("接口", selection: $store.selectedPath) {
                        ForEach(store.devices) { device in Text("\(device.title) · \(device.detail)").tag(device.pathHex) }
                    }.disabled(store.isBusy)
                    .onChange(of: store.selectedPath) { _ in store.deviceChanged() }
                    HStack {
                        Toggle("已按住减号键连接，进入 DFU", isOn: $store.dfuConfirmed)
                            .disabled(store.isBusy)
                        Spacer()
                        Button("读取设备信息") { store.probe() }.disabled(!store.canProbe)
                    }
                }
                if let identity = store.identity {
                    HStack(spacing: 10) {
                        Label("K2 已确认", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("当前版本 \(identity.currentVersion ?? "未知")").fontWeight(.semibold)
                        Spacer()
                        Text(identity.bootStrings.last ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
