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
    /// Navigation sidebar visibility, driven by `NavigationSidebarToggle` instead
    /// of the system toolbar item.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    private var section: ToolSection { selection ?? .monitor }

    var body: some View {
        // Both columns claim the traffic-light strip: the sidebar fills it with
        // its own header row, the workspace top bar starts at the very top, so
        // the window never reserves an empty band above the workspace.
        NavigationSplitView(columnVisibility: $columnVisibility) {
            navigationSidebar.ignoresSafeArea(edges: .top)
        } detail: {
            workspaceColumn.ignoresSafeArea(edges: .top)
        }
        .frame(minWidth: 1100, minHeight: 720)
        .task { store.checkDevicePresence() }
        .onReceive(Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()) { _ in
            store.checkDevicePresence()
        }
        .navigationTitle(section.rawValue)
        .alert("恢复\(restoreIntent?.kind.title ?? "资源")备份？", isPresented: Binding(get: { restoreIntent != nil }, set: { if !$0 { restoreIntent = nil } })) {
            Button("取消", role: .cancel) { restoreIntent = nil }
            Button("备份并恢复") { if let intent = restoreIntent { store.writeResource(intent) }; restoreIntent = nil }
        } message: {
            Text("恢复到备份中的完整资源扇区。后台会核对备份摘要和设备身份，先双遍备份当前数据，再擦写和完整读回校验。请保持连接")
        }
    }

    // MARK: - Navigation sidebar

    private var sidebarExpanded: Bool { columnVisibility != .detailOnly }

    private var sidebarToggle: Binding<Bool> {
        Binding(get: { sidebarExpanded },
                set: { expanded in
                    withAnimation(.easeInOut(duration: 0.24)) {
                        columnVisibility = expanded ? .all : .detailOnly
                    }
                })
    }

    private var navigationSidebar: some View {
        List(selection: $selection) {
            navigationRow(.monitor)
            navigationRow(.firmware)
            Section("自定义") { navigationRow(.dial); navigationRow(.startup) }
            Section("高级工具") { navigationRow(.emark) }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 178, ideal: LayoutMetrics.navigationSidebarIdealWidth, max: 250)
        // Sits on the sidebar's own background so the two never show a seam.
        .safeAreaInset(edge: .top, spacing: 0) { sidebarHeader }
    }

    /// Keeps the sidebar's collapse control aligned with the central title group
    /// instead of leaving it in the traffic-light strip.
    private var sidebarHeader: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            NavigationSidebarToggle(expanded: sidebarToggle, size: LayoutMetrics.navigationSidebarToggleSize)
        }
        .frame(height: LayoutMetrics.navigationSidebarHeaderHeight)
        .padding(.horizontal, LayoutMetrics.navigationSidebarHeaderInset)
    }

    // MARK: - Detail column

    private var workspaceColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                workspaceWithTopBar
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                connectionSidebar
            }
            .animation(LayoutMetrics.connectionSidebarAnimation, value: connectionExpanded)
            Divider()
            TaskStatusBar(store: store, monitor: monitor)
        }
    }

    @ViewBuilder
    private var workspaceWithTopBar: some View {
        if #available(macOS 26.0, *) {
            workspace
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaBar(edge: .top, spacing: 0) {
                    workspaceToolbar(usesScrollEdge: true)
                }
                // Apply outside the bar so its own edge configuration cannot
                // override the requested style.
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            VStack(spacing: 0) {
                workspaceToolbar(usesScrollEdge: false)
                workspace.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func workspaceToolbar(usesScrollEdge: Bool) -> some View {
        WorkspaceToolbar(section: section, store: store, picture: picture,
                         emark: emark, monitor: monitor,
                         connectionExpanded: $connectionExpanded,
                         sidebarExpanded: sidebarToggle,
                         onChooseResourceBackup: { restoreIntent = store.chooseResourceBackup() },
                         usesScrollEdge: usesScrollEdge)
    }

    private var connectionSidebar: some View {
        HStack(spacing: 0) {
            Divider()
            ConnectionSidebar(updater: store, monitor: monitor, picture: picture, section: section)
                .frame(width: LayoutMetrics.connectionSidebarWidth)
                .clipped()
        }
        .frame(width: connectionExpanded ? LayoutMetrics.connectionSidebarWidth + 1 : 0,
               alignment: .trailing)
        .clipped()
        .opacity(connectionExpanded ? 1 : 0)
        .offset(x: connectionExpanded ? 0 : 24)
        .allowsHitTesting(connectionExpanded)
    }

    private func navigationRow(_ section: ToolSection) -> some View {
        Label(section.rawValue, systemImage: section.symbol).tag(section)
    }

    @ViewBuilder private var workspace: some View {
        switch section {
        case .monitor:
            MonitorView(monitor: monitor, updater: store, showConnection: revealConnectionSidebar)
        case .firmware:
            ScrollView {
                FirmwareView(store: store, showConnection: revealConnectionSidebar)
                    .padding(LayoutMetrics.pagePadding).frame(maxWidth: .infinity, alignment: .leading)
            }
        case .dial:
            PictureView(picture: picture, store: store, startup: false)
        case .startup:
            PictureView(picture: picture, store: store, startup: true)
        case .emark:
            EmarkView(emark: emark, store: store)
        }
    }

    private func revealConnectionSidebar() {
        withAnimation(LayoutMetrics.connectionSidebarAnimation) {
            connectionExpanded = true
        }
    }
}
