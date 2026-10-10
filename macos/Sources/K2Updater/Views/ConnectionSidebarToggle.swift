import SwiftUI
import K2Core

/// Expand/collapse control for the right-hand connection sidebar.
///
/// It lives at the trailing edge of the central top bar — the sidebar side of the
/// window — instead of the centred window toolbar, so the entry point stays
/// visible whether the sidebar is expanded or collapsed.
struct ConnectionSidebarToggle: View {
    @ObservedObject var updater: UpdaterStore
    @ObservedObject var monitor: MonitorStore
    @Binding var expanded: Bool
    var onPressChanged: (Bool) -> Void = { _ in }

    private var summary: ConnectionPresentation { .current(updater: updater, monitor: monitor) }
    private var connected: Bool {
        if monitor.connected {
            return monitor.latest != nil && monitor.state?.stale != true && !monitor.disconnecting
        }
        return updater.selectedDevice != nil && updater.dfuConfirmed && updater.identity?.confirmedK2 == true
    }
    private var description: String {
        "\(summary.title) · \(expanded ? "收起" : "展开")设备连接栏"
    }

    var body: some View {
        Button {
            withAnimation(LayoutMetrics.connectionSidebarAnimation) {
                expanded.toggle()
            }
        } label: {
            Group {
                if connected {
                    Image(systemName: "link")
                        .font(.system(size: LayoutMetrics.toolbarActionIconSize, weight: .medium))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.green)
                } else {
                    BrokenLinkSymbol()
                        .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: LayoutMetrics.toolbarActionIconSize,
                               height: LayoutMetrics.toolbarActionIconSize)
                        .foregroundStyle(.red)
                }
            }
            .frame(width: LayoutMetrics.toolbarActionHitSize,
                   height: LayoutMetrics.toolbarActionHitSize)
            // Define the hit region inside the label: transparent padding in a
            // custom button style otherwise only hits the drawn symbol.
            .contentShape(Rectangle())
            .contentTransition(.identity)
            // Sidebar movement and glass feedback may animate; the status
            // symbol itself must not inherit their animation transactions.
            .transaction { $0.animation = nil }
        }
        .buttonStyle(ToolbarGlassPressObserver(onPressChanged: onPressChanged))
        .frame(width: LayoutMetrics.toolbarActionHitSize,
               height: LayoutMetrics.toolbarActionHitSize)
        .contentShape(Rectangle())
        .help(description)
        .accessibilityLabel(description)
    }
}

/// Draw an open link with a diagonal slash for the disconnected state.
private struct BrokenLinkSymbol: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0.48, 0.32))
        path.addLine(to: point(0.62, 0.18))
        path.addCurve(to: point(0.82, 0.38), control1: point(0.83, -0.02), control2: point(1.02, 0.18))
        path.addLine(to: point(0.68, 0.52))
        path.move(to: point(0.32, 0.48))
        path.addLine(to: point(0.18, 0.62))
        path.addCurve(to: point(0.38, 0.82), control1: point(-0.02, 0.83), control2: point(0.18, 1.02))
        path.addLine(to: point(0.52, 0.68))
        path.move(to: point(0.18, 0.18))
        path.addLine(to: point(0.82, 0.82))
        return path
    }
}
