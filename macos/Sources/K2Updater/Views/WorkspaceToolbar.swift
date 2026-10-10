import SwiftUI
import K2Core

/// The central panel's top bar.
///
/// It carries the single page title (mirroring the left sidebar selection), the
/// page's contextual state, the page-level file actions and — at its trailing
/// edge, against the connection sidebar — the expand/collapse control for that
/// sidebar. At its leading edge it shows the navigation sidebar's expand button
/// while that sidebar is collapsed, since the sidebar's own control goes with it.
struct WorkspaceToolbar: View {
    let section: ToolSection
    @ObservedObject var store: UpdaterStore
    @ObservedObject var picture: PictureStore
    @ObservedObject var emark: EmarkStore
    @ObservedObject var monitor: MonitorStore
    @Binding var connectionExpanded: Bool
    @Binding var sidebarExpanded: Bool
    let onChooseResourceBackup: () -> Void
    var usesScrollEdge = false
    @GestureState private var maintenancePressed = false
    @State private var connectionPressed = false
    private var toolbarActionPressed: Bool { maintenancePressed || connectionPressed }

    private var editor: Bool { section == .dial || section == .startup || section == .emark }
    private var isEmark: Bool { section == .emark }
    private var dirty: Bool { isEmark ? emark.dirty || !emark.invalidFields.isEmpty : picture.dirty }

    private var subtitle: String {
        if editor {
            return (isEmark ? emark.projectURL?.lastPathComponent : picture.projectURL?.lastPathComponent) ?? "未命名工程"
        }
        return section == .monitor ? "实时曲线与采集记录" : "检查固件、备份并更新设备"
    }

    var body: some View {
        HStack(spacing: 14) {
            // The navigation sidebar folds away with its own toggle, so while it
            // is collapsed the top bar keeps a compact way back — placed clear of
            // the window traffic lights, which the workspace now sits beneath.
            if !sidebarExpanded {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    NavigationSidebarToggle(expanded: $sidebarExpanded,
                                            size: LayoutMetrics.navigationSidebarToggleSize)
                }
                .frame(width: LayoutMetrics.trafficLightTrailing - LayoutMetrics.pagePadding)
                .offset(x: LayoutMetrics.navigationSidebarCollapsedToggleTrailingOffset, y: 0)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(section.rawValue)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, sidebarExpanded ? 0 : 25)

            if editor { saveState }

            Spacer(minLength: 12)

            if editor { editorActions }

            toolbarActionGroup
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .modifier(SystemGlassSurface(active: !usesScrollEdge))
        .disabled(store.isBusy)
    }

    private var saveState: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dirty ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
            Text(dirty ? "未保存" : "已保存")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var maintenanceMenu: some View {
        Menu {
            Button { onChooseResourceBackup() } label: {
                Label("恢复资源备份", systemImage: "clock.arrow.circlepath")
            }
            .disabled(!store.canUseResources)
            Divider()
            Button { store.showBackup() } label: {
                Label("打开备份文件夹", systemImage: "folder")
            }
            .disabled(store.backupPath == nil)
            Button { store.showLog() } label: {
                Label("查看日志", systemImage: "doc.text")
            }
            .disabled(store.tracePath == nil)
        } label: {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: LayoutMetrics.toolbarActionIconSize, weight: .medium))
                .frame(width: LayoutMetrics.toolbarActionHitSize,
                       height: LayoutMetrics.toolbarActionHitSize)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: LayoutMetrics.toolbarActionHitSize,
               height: LayoutMetrics.toolbarActionHitSize)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .updating($maintenancePressed) { _, isPressed, _ in isPressed = true })
        .help("维护")
        .accessibilityLabel("维护")
    }

    @ViewBuilder private var toolbarActionGroup: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: LayoutMetrics.toolbarGlassBlendSpacing) {
                toolbarActionButtons
            }
        } else {
            toolbarActionButtons
        }
    }

    private var toolbarActionButtons: some View {
        HStack(spacing: toolbarActionPressed ? LayoutMetrics.toolbarActionPressedSpacing : LayoutMetrics.toolbarActionSpacing) {
            maintenanceMenu
                .modifier(SystemGlassToolbarButtonSurface())
            ConnectionSidebarToggle(updater: store, monitor: monitor, expanded: $connectionExpanded,
                                    onPressChanged: { connectionPressed = $0 })
                .modifier(SystemGlassToolbarButtonSurface())
        }
        // Keep the group's width and center steady so both buttons move inward equally.
        .frame(width: LayoutMetrics.toolbarActionHitSize * 2 + LayoutMetrics.toolbarActionSpacing,
               alignment: .center)
        .animation(.easeInOut(duration: 0.16), value: toolbarActionPressed)
        .buttonStyle(.plain)
    }

    @ViewBuilder private var editorActions: some View {
        Menu("文件") {
            Button("新建工程") {
                if isEmark { emark.newProject() } else { picture.newProject() }
            }
            Button("打开工程") {
                if isEmark { emark.open() } else { picture.open() }
            }
            Button("另存为") {
                if isEmark { emark.save(asNew: true) } else { picture.save(asNew: true) }
            }
            Divider()
            if isEmark {
                Button("导入 .wtemark") { emark.importRecords() }
                    .disabled(emark.bank.count >= 10 || !emark.invalidFields.isEmpty)
                Button("导出配置") { emark.export() }
                    .disabled(emark.record == nil || !emark.invalidFields.isEmpty)
            } else {
                Button("导出布局 .pic") { picture.export(.layout) }
                Button("导出背景 BMP") { picture.export(.background) }
                    .disabled(picture.project.background == nil)
                Button("导出开机图 BMP") { picture.export(.startup) }
                    .disabled(picture.project.startup == nil)
            }
        }
        .fixedSize()

        Button("保存") {
            if isEmark { emark.save() } else { picture.save() }
        }

        Button("↶") {
            if isEmark { emark.undo() } else { picture.undo() }
        }
        .disabled(isEmark ? !emark.undoAvailable : !picture.undoAvailable)
        .help("撤销")
        .font(.title3)

        Button("↷") {
            if isEmark { emark.redo() } else { picture.redo() }
        }
        .disabled(isEmark ? !emark.redoAvailable : !picture.redoAvailable)
        .help("重做")
        .font(.title3)
    }
}
