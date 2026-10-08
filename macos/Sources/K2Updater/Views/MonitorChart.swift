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
    @State private var dragStart: Double?
    @State private var cursor: Double?
    private var color: Color {
        switch channel { case .voltage: return .blue; case .current: return .orange; case .power: return .green; default: return .purple }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(channel.title) · \(channel.unit)").font(.callout.bold())
                Spacer()
                if let cursor, let point = points.min(by: { abs($0.time - cursor) < abs($1.time - cursor) }) {
                    Text("\(MonitorFormat.elapsed(point.time))  \(MonitorFormat.number(point.value(channel))) \(channel.unit)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Chart {
                ForEach(points) { point in
                    if let value = point.value(channel) {
                        LineMark(x: .value("时间", point.time), y: .value(channel.title, value), series: .value("分段", point.segment))
                            .foregroundStyle(color).interpolationMethod(.linear)
                    }
                }
                if let selection {
                    RectangleMark(xStart: .value("开始", selection.lowerBound), xEnd: .value("结束", selection.upperBound))
                        .foregroundStyle(Color.accentColor.opacity(0.12))
                }
                if let cursor { RuleMark(x: .value("游标", cursor)).foregroundStyle(.secondary.opacity(0.4)) }
            }
            .chartXScale(domain: start...max(start + 0.001, end))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine(); AxisTick()
                    AxisValueLabel { if let time = value.as(Double.self) { Text(MonitorFormat.elapsed(time)).font(.caption2) } }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point): cursor = proxy.value(atX: point.x - geometry[proxy.plotAreaFrame].origin.x)
                            case .ended: cursor = nil
                            }
                        }
                        .gesture(DragGesture(minimumDistance: 3)
                            .onChanged { value in
                                if dragStart == nil { dragStart = proxy.value(atX: value.startLocation.x - geometry[proxy.plotAreaFrame].origin.x) }
                                cursor = proxy.value(atX: value.location.x - geometry[proxy.plotAreaFrame].origin.x)
                            }
                            .onEnded { value in
                                if let lo = dragStart, let hi: Double = proxy.value(atX: value.location.x - geometry[proxy.plotAreaFrame].origin.x) {
                                    onSelect(max(start, min(end, lo)), max(start, min(end, hi)))
                                }
                                dragStart = nil
                            })
                }
            }
            .frame(height: 145)
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
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
