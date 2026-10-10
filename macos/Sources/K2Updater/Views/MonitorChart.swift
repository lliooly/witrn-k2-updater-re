import AppKit
import Charts
import SwiftUI
import K2Core

struct MonitorChart: View {
    let points: [MonitorSample]
    let channel: MonitorChannel
    let start: Double
    let end: Double
    let selection: ClosedRange<Double>?
    let onSelect: (Double, Double) -> Void
    // The owner retains the reference without observing it. Only the readout
    // and overlay subscribe, so moving the cursor never rebuilds LineMarks.
    @State private var interaction = MonitorChartInteraction()
    private var color: Color {
        switch channel { case .voltage: return .blue; case .current: return .orange; case .power: return .green; default: return .purple }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(channel.title) · \(channel.unit)").font(.callout.bold())
                Spacer()
                MonitorCursorReadout(interaction: interaction, points: points, channel: channel)
            }
            .frame(height: 18)
            Chart {
                if #available(macOS 15, *) {
                    // One vectorized plot preserves every query point and each
                    // segment without creating thousands of SwiftUI marks.
                    LinePlot(MonitorLinePoint.project(points, channel: channel),
                             x: .value("时间", \.time), y: .value(channel.title, \.value),
                             series: .value("分段", \.segment))
                        .foregroundStyle(color).interpolationMethod(.linear)
                } else {
                    ForEach(points) { point in
                        if let value = point.value(channel) {
                            LineMark(x: .value("时间", point.time), y: .value(channel.title, value), series: .value("分段", point.segment))
                                .foregroundStyle(color).interpolationMethod(.linear)
                        }
                    }
                }
                if let selection {
                    RectangleMark(xStart: .value("开始", selection.lowerBound), xEnd: .value("结束", selection.upperBound))
                        .foregroundStyle(Color.accentColor.opacity(0.12))
                }
            }
            .chartXScale(domain: start...max(start + 0.001, end))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine(); AxisTick()
                    AxisValueLabel { if let time = value.as(Double.self) { Text(MonitorFormat.elapsed(time)).font(.caption2) } }
                }
            }
            .chartOverlay { proxy in
                MonitorChartOverlay(interaction: interaction, proxy: proxy,
                                    start: start, end: end, onSelect: onSelect)
            }
            .frame(height: 145)
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A projection, not downsampling: matches the original LineMark's nil filter.
struct MonitorLinePoint: Equatable {
    let time: Double
    let value: Double
    let segment: Int

    static func project(_ points: [MonitorSample], channel: MonitorChannel) -> [Self] {
        points.compactMap { point in
            point.value(channel).map { Self(time: point.time, value: $0, segment: point.segment) }
        }
    }
}

private final class MonitorChartInteraction: ObservableObject {
    @Published var cursor: Double?
}

private struct MonitorCursorReadout: View {
    @ObservedObject var interaction: MonitorChartInteraction
    let points: [MonitorSample]
    let channel: MonitorChannel

    var body: some View {
        if let cursor = interaction.cursor, let point = MonitorSample.nearest(in: points, to: cursor) {
            Text("\(MonitorFormat.elapsed(point.time))  \(MonitorFormat.number(point.value(channel))) \(channel.unit)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct MonitorChartOverlay: View {
    @ObservedObject var interaction: MonitorChartInteraction
    let proxy: ChartProxy
    let start: Double
    let end: Double
    let onSelect: (Double, Double) -> Void
    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { geometry in
            let plot = geometry[proxy.plotAreaFrame]
            ZStack(alignment: .topLeading) {
                if let cursor = interaction.cursor, let x = proxy.position(forX: cursor),
                   x >= 0, x <= plot.width {
                    Path { path in
                        path.move(to: CGPoint(x: plot.minX + x, y: plot.minY))
                        path.addLine(to: CGPoint(x: plot.minX + x, y: plot.maxY))
                    }
                    .stroke(.secondary.opacity(0.4), lineWidth: 1)
                    .allowsHitTesting(false)
                }
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            interaction.cursor = proxy.value(atX: point.x - plot.minX)
                        case .ended: interaction.cursor = nil
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            if dragStart == nil { dragStart = proxy.value(atX: value.startLocation.x - plot.minX) }
                            interaction.cursor = proxy.value(atX: value.location.x - plot.minX)
                        }
                        .onEnded { value in
                            if let lo = dragStart, let hi: Double = proxy.value(atX: value.location.x - plot.minX) {
                                onSelect(max(start, min(end, lo)), max(start, min(end, hi)))
                            }
                            dragStart = nil
                        })
            }
        }
    }
}

struct MonitorPlotExport: View {
    let points: [MonitorSample]
    let channels: [MonitorChannel]
    let start: Double
    let end: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WITRN K2 · \(MonitorFormat.elapsed(start)) — \(MonitorFormat.elapsed(end))").font(.title3)
            ForEach(channels) { channel in
                MonitorChart(points: points, channel: channel, start: start, end: end, selection: nil, onSelect: { _, _ in })
            }
        }.padding(22).frame(width: 1100).background(Color(nsColor: .windowBackgroundColor))
    }
}
