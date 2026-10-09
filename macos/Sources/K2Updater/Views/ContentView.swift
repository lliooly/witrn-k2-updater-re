import SwiftUI
import K2Core

enum ToolSection: String, CaseIterable, Identifiable {
    case monitor = "上位机", firmware = "固件升级", dial = "表盘", startup = "开机图", emark = "虚拟 E-Mark"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .firmware: return "arrow.triangle.2.circlepath"
        case .dial: return "speedometer"
        case .startup: return "photo"
        case .emark: return "cable.connector"
        case .monitor: return "chart.xyaxis.line"
        }
    }
}

struct ContentView: View {
    @ObservedObject var store: UpdaterStore
    @ObservedObject var picture: PictureStore
    @ObservedObject var emark: EmarkStore
    @ObservedObject var monitor: MonitorStore
    @Binding var selection: ToolSection?
    @AppStorage("connectionSidebarExpanded") private var connectionExpanded = true
    @State private var restoreIntent: ResourceWriteIntent?
    private var section: ToolSection { selection ?? .monitor }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                navigationRow(.monitor)
                navigationRow(.firmware)
                Section("自定义") { navigationRow(.dial); navigationRow(.startup) }
                Section("高级工具") { navigationRow(.emark) }
            }.listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 145, ideal: 155, max: 180)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 4) {
                        Text("WITRN K2").font(.callout.weight(.semibold))
                        Text("独立维护工具").font(.caption).foregroundStyle(.secondary)
                    }.padding(16)
                }
        } detail: {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        WorkspaceToolbar(section: section, store: store, picture: picture, emark: emark)
                        Divider()
                        workspace.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Keep the connection component at the same identity on every page.
                    // Hiding changes only its width; no appearance hook owns a session.
                    Divider().opacity(connectionExpanded ? 1 : 0)
                    ConnectionSidebar(updater: store, monitor: monitor, picture: picture, section: section)
                        .frame(width: connectionExpanded ? 260 : 0)
                        .clipped().allowsHitTesting(connectionExpanded).accessibilityHidden(!connectionExpanded)
                }
                Divider()
                TaskStatusBar(store: store, monitor: monitor)
            }
        }
        .frame(minWidth: 1100, minHeight: 720)
        .task { store.refreshDevices() }
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Button { restoreIntent = store.chooseResourceBackup() } label: {
                        Label("恢复资源备份", systemImage: "clock.arrow.circlepath")
                    }.disabled(!store.canUseResources)
                    Divider()
                    Button { store.showBackup() } label: {
                        Label("打开备份文件夹", systemImage: "folder")
                    }.disabled(store.backupPath == nil)
                    Button { store.showLog() } label: {
                        Label("查看日志", systemImage: "doc.text")
                    }.disabled(store.tracePath == nil)
                } label: {
                    Label("维护", systemImage: "wrench.and.screwdriver")
                }
                ConnectionToolbarButton(updater: store, monitor: monitor, expanded: $connectionExpanded)
            }
        }
        .alert("恢复\(restoreIntent?.kind.title ?? "资源")备份？", isPresented: Binding(get: { restoreIntent != nil }, set: { if !$0 { restoreIntent = nil } })) {
            Button("取消", role: .cancel) { restoreIntent = nil }
            Button("备份并恢复") { if let intent = restoreIntent { store.writeResource(intent) }; restoreIntent = nil }
        } message: {
            Text("恢复到备份中的完整资源扇区。后台会核对备份摘要和设备身份，先双遍备份当前数据，再擦写和完整读回校验。请保持连接")
        }
    }

    private func navigationRow(_ section: ToolSection) -> some View {
        Label(section.rawValue, systemImage: section.symbol).tag(section)
    }

    @ViewBuilder private var workspace: some View {
        switch section {
        case .monitor:
            MonitorView(monitor: monitor, updater: store, showConnection: { connectionExpanded = true })
        case .firmware:
            ScrollView {
                FirmwareView(store: store, showConnection: { connectionExpanded = true })
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
        case .dial:
            PictureView(picture: picture, store: store, startup: false)
        case .startup:
            PictureView(picture: picture, store: store, startup: true)
        case .emark:
            EmarkView(emark: emark, store: store)
        }
    }
}
