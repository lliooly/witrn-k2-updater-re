import SwiftUI
import K2Core

enum ToolSection: String, CaseIterable, Identifiable {
    case firmware = "固件升级", dial = "表盘", startup = "开机图", emark = "虚拟 E-Mark"
    var id: String { rawValue }
    var symbol: String { switch self { case .firmware: return "arrow.triangle.2.circlepath"; case .dial: return "speedometer"; case .startup: return "photo"; case .emark: return "cable.connector" } }
}

struct ContentView: View {
    @ObservedObject var store: UpdaterStore
    @ObservedObject var picture: PictureStore
    @ObservedObject var emark: EmarkStore
    @Binding var selection: ToolSection?
    @State private var restoreIntent: ResourceWriteIntent?
    var body: some View {
        NavigationSplitView {
            List(ToolSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.symbol).tag(section)
            }.navigationSplitViewColumnWidth(min: 130, ideal: 155, max: 180)
            .safeAreaInset(edge: .bottom) { Text("WITRN K2\n独立维护工具").font(.caption).foregroundStyle(.secondary).padding(16) }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DeviceCard(store: store)
                    switch selection ?? .firmware {
                    case .firmware: FirmwareView(store: store)
                    case .dial: PictureView(picture: picture, store: store, startup: false)
                    case .startup: PictureView(picture: picture, store: store, startup: true)
                    case .emark: EmarkView(emark: emark, store: store)
                    }
                    ProgressCard(store: store)
                    HStack {
                        if store.canCancel { Button("取消只读操作") { store.cancel() } }
                        Spacer()
                        Button("恢复资源备份…") { restoreIntent = store.chooseResourceBackup() }.disabled(!store.canUseResources)
                        Button("打开备份文件夹") { store.showBackup() }.disabled(store.backupPath == nil)
                        Button("查看日志") { store.showLog() }.disabled(store.tracePath == nil)
                    }
                }.padding(22)
            }.frame(minWidth: 775)
        }
        .frame(minWidth: 950, minHeight: 720)
        .task { store.refreshDevices() }
        .toolbar {
            if selection == .emark {
                Button { emark.newProject() } label: { Label("新建配置集合", systemImage: "doc.badge.plus") }.disabled(store.isBusy)
                Button { emark.undo() } label: { Label("撤销", systemImage: "arrow.uturn.backward") }.disabled(store.isBusy || !emark.undoAvailable)
                Button { emark.redo() } label: { Label("重做", systemImage: "arrow.uturn.forward") }.disabled(store.isBusy || !emark.redoAvailable)
            } else if selection != .firmware {
                Button { picture.newProject() } label: { Label("新建工程", systemImage: "doc.badge.plus") }.disabled(store.isBusy)
                Button { picture.undo() } label: { Label("撤销", systemImage: "arrow.uturn.backward") }.disabled(store.isBusy || !picture.undoAvailable)
                Button { picture.redo() } label: { Label("重做", systemImage: "arrow.uturn.forward") }.disabled(store.isBusy || !picture.redoAvailable)
            }
        }
        .alert("恢复\(restoreIntent?.kind.title ?? "资源")备份？", isPresented: Binding(get: { restoreIntent != nil }, set: { if !$0 { restoreIntent = nil } })) {
            Button("取消", role: .cancel) { restoreIntent = nil }
            Button("备份并恢复") { if let intent = restoreIntent { store.writeResource(intent) }; restoreIntent = nil }
        } message: {
            Text("恢复到备份中的完整资源扇区。后台会核对备份摘要和设备身份，先双遍备份当前数据，再擦写和完整读回校验。请保持连接。")
        }
    }
}

struct FirmwareView: View {
    @ObservedObject var store: UpdaterStore
    @State private var confirmUpgrade = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("固件升级").font(.title2).fontWeight(.semibold)
            FirmwareCard(store: store)
            HStack {
                Button("仅备份固件") { store.backup() }.disabled(!store.canUseResources)
                Spacer()
                Button("备份并升级") { confirmUpgrade = true }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!store.canUpgrade)
            }
        }
        .alert("备份并升级到 \(store.firmware?.version ?? "")？", isPresented: $confirmUpgrade) {
            Button("取消", role: .cancel) {}
            Button("备份并升级") { store.upgrade() }
        } message: {
            Text("先完整读取两遍并核对备份，再擦除应用区并写入所选固件。当前 \(store.identity?.currentVersion ?? "未知") → 目标 \(store.firmware?.version ?? "未知")。升级期间请保持连接。")
        }
    }
}
