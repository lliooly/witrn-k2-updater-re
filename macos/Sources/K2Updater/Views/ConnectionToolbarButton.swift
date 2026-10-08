import SwiftUI

struct ConnectionToolbarButton: View {
    @ObservedObject var updater: UpdaterStore
    @ObservedObject var monitor: MonitorStore
    @Binding var expanded: Bool

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
        Button { expanded.toggle() } label: {
            Group {
                if connected {
                    Image(systemName: "link").symbolRenderingMode(.palette)
                        .foregroundStyle(.green)
                } else {
                    BrokenLinkSymbol().stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(.secondary)
                }
            }.frame(width: 20, height: 20)
        }.help(description).accessibilityLabel(description)
    }
}

/// Draw open chain ends without relying on a link.slash system symbol.
/// The disconnected state remains visible without relying on color.
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
        return path
    }
}
