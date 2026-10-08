import SwiftUI
import K2Core

struct MonitorStatisticsView: View {
    let statistics: MonitorStatistics
    var body: some View {
        GroupBox("区间统计 · 原始样本计算") {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(statistics.count) 个样本 · 时间跨度 \(MonitorFormat.elapsed(statistics.span)) · 有效覆盖 \(MonitorFormat.elapsed(statistics.coverage))")
                    .font(.callout.monospacedDigit())
                Grid(alignment: .leading, horizontalSpacing: 25, verticalSpacing: 6) {
                    GridRow { Text("测量"); Text("最小"); Text("最大"); Text("时间加权平均") }.font(.caption).foregroundStyle(.secondary)
                    ForEach(MonitorChannel.allCases) { channel in
                        if let value = statistics.channels[channel.rawValue] {
                            GridRow {
                                Text("\(channel.title) (\(channel.unit))")
                                Text(MonitorFormat.number(value.min)); Text(MonitorFormat.number(value.max)); Text(MonitorFormat.number(value.average))
                            }.font(.callout.monospacedDigit())
                        }
                    }
                }
                Divider()
                Grid(alignment: .leading, horizontalSpacing: 25, verticalSpacing: 6) {
                    GridRow { Text("电脑积分"); Text("正向"); Text("反向"); Text("净值"); Text("绝对累计") }.font(.caption).foregroundStyle(.secondary)
                    GridRow {
                        Text("电量 (mAh)")
                        Text(MonitorFormat.number(statistics.ahPositive * 1000)); Text(MonitorFormat.number(statistics.ahNegative * 1000))
                        Text(MonitorFormat.number(statistics.ahNet * 1000)); Text(MonitorFormat.number(statistics.ahAbsolute * 1000))
                    }
                    GridRow {
                        Text("能量 (mWh)")
                        Text(MonitorFormat.number(statistics.whPositive * 1000)); Text(MonitorFormat.number(statistics.whNegative * 1000))
                        Text(MonitorFormat.number(statistics.whNet * 1000)); Text(MonitorFormat.number(statistics.whAbsolute * 1000))
                    }
                }.font(.callout.monospacedDigit())
                Text("占全记录：有效时长 \(percent("coverage")) · 电量 \(percent("ah_absolute")) · 能量 \(percent("wh_absolute"))")
                    .font(.caption).foregroundStyle(.secondary)
                Text("暂停、断连和长间隔不积分；方向按 K2 电流符号。设备累计 Ah/Wh 与电脑积分各自独立。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func percent(_ key: String) -> String { MonitorFormat.number(statistics.percentages[key] ?? nil, digits: 1) + "%" }
}
