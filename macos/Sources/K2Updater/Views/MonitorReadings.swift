import SwiftUI
import K2Core

/// Only these display leaves observe the 10 Hz telemetry stream.
struct MonitorReadings: View {
    @ObservedObject var telemetry: MonitorTelemetry
    @Binding var extraReadings: Bool

    // MARK: - Readings panel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 0) {
                reading("电压", telemetry.latest?.voltage, "V")
                Divider().frame(height: 60).padding(.horizontal, 24)
                reading("电流", telemetry.latest?.current, "A")
                Divider().frame(height: 60).padding(.horizontal, 24)
                reading("功率", telemetry.latest?.power, "W")
            }
            .opacity(telemetry.state?.stale == true ? 0.35 : 1)

            if extraReadings {
                Divider()
                detailGrid
            }

            Button {
                extraReadings.toggle()
            } label: {
                HStack(spacing: 5) {
                    Text(extraReadings ? "收起详细信息" : "显示详细信息")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Image(systemName: extraReadings ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
        .systemPanel()
    }

    private func reading(_ title: String, _ value: Double?, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(MonitorFormat.number(value))
                    .font(.system(size: 42, weight: .regular, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 32) {
                detailReading("内部温度", MonitorFormat.number(telemetry.latest?.tempIn), "°C")
                detailReading("外部温度", MonitorFormat.number(telemetry.latest?.tempOut), "°C")
                Spacer(minLength: 0)
            }
            HStack(spacing: 32) {
                detailReading("D+", MonitorFormat.number(telemetry.latest?.dp), "V")
                detailReading("D−", MonitorFormat.number(telemetry.latest?.dn), "V")
                detailReading("累计", "\(MonitorFormat.number(telemetry.latest?.ah)) Ah",
                              "· \(MonitorFormat.number(telemetry.latest?.wh)) Wh")
                Spacer(minLength: 0)
            }
            HStack(spacing: 32) {
                detailReading("记录组", telemetry.latest?.group.map(String.init) ?? "—", "")
                detailReading("设备记录", deviceTime(telemetry.latest?.recordSeconds), "")
                detailReading("接收", "\(MonitorFormat.number(telemetry.state?.receiveRate, digits: 1))/s",
                              "· \(telemetry.state?.recordCount ?? 0) 样本")
                Spacer(minLength: 0)
            }
            if let invalid = telemetry.state?.invalid, invalid > 0 {
                Text("⚠ 已忽略 \(invalid) 个无效遥测包")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout.monospacedDigit())
    }

    private func detailReading(_ title: String, _ value: String, _ suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value + (suffix.isEmpty ? "" : " " + suffix))
                .font(.callout.monospacedDigit())
        }
    }

    private func deviceTime(_ seconds: Int?) -> String {
        seconds.map { MonitorFormat.elapsed(Double($0)) } ?? "—"
    }
}

struct MonitorCaptureProgress: View {
    @ObservedObject var telemetry: MonitorTelemetry
    var showsElapsed = true

    var body: some View {
        Text(showsElapsed
             ? "\(telemetry.state?.recordCount ?? 0) 样本 · \(MonitorFormat.elapsed(telemetry.state?.elapsed ?? 0))"
             : "\(telemetry.state?.recordCount ?? 0) 样本")
            .monospacedDigit()
    }
}

/// Query start/finish updates only this indicator. Controls can submit a new
/// request while the store cancels/replaces an older read-only query.
struct MonitorQueryProgress: View {
    @ObservedObject var activity: MonitorQueryActivity

    var body: some View {
        ZStack {
            if activity.isRunning { ProgressView().controlSize(.small) }
        }
        .frame(width: 16, height: 16)
        .accessibilityLabel(activity.isRunning ? "正在刷新曲线" : "")
    }
}
