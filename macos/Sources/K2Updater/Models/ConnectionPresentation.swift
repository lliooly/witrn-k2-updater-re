import SwiftUI

/// A display-only summary. It never starts, stops or probes a device session.
enum ConnectionPresentation: Equatable {
    case unavailable, available, waiting, live, recording, paused, stale, disconnecting
    case dfuDeclared, dfuReady, busy, error

    static func capture(connected: Bool, disconnecting: Bool, hasSample: Bool,
                        stale: Bool, recording: Bool, paused: Bool) -> Self? {
        guard connected else { return nil }
        if disconnecting { return .disconnecting }
        if stale { return .stale }
        if !hasSample { return .waiting }
        if recording { return paused ? .paused : .recording }
        return .live
    }

    @MainActor static func current(updater: UpdaterStore, monitor: MonitorStore) -> Self {
        if updater.isBusy { return .busy }
        if monitor.errorMessage != nil { return .error }
        if let capture = capture(connected: monitor.connected, disconnecting: monitor.disconnecting,
                                 hasSample: monitor.latest != nil, stale: monitor.state?.stale == true,
                                 recording: monitor.recording, paused: monitor.paused) { return capture }
        guard updater.selectedDevice != nil else { return .unavailable }
        if updater.identity?.confirmedK2 == true && updater.dfuConfirmed { return .dfuReady }
        if updater.dfuConfirmed { return .dfuDeclared }
        return .available
    }

    var title: String {
        switch self {
        case .unavailable: return "未选择设备"
        case .available: return "已发现接口 · 未连接"
        case .waiting: return "等待有效遥测"
        case .live: return "实时预览"
        case .recording: return "正在记录"
        case .paused: return "记录已暂停"
        case .stale: return "遥测已过期"
        case .disconnecting: return "正在保存并断开"
        case .dfuDeclared: return "DFU 待读取确认"
        case .dfuReady: return "DFU 设备已确认"
        case .busy: return "正在处理任务"
        case .error: return "采集连接异常"
        }
    }
    var symbol: String {
        switch self {
        case .unavailable, .available: return "cable.connector"
        case .waiting, .disconnecting, .busy: return "hourglass"
        case .stale, .error: return "exclamationmark.triangle"
        case .dfuDeclared: return "questionmark.circle"
        case .paused: return "pause.circle"
        case .recording: return "record.circle"
        case .live, .dfuReady: return "checkmark.circle"
        }
    }
    var color: Color {
        switch self {
        case .live, .dfuReady: return .green
        case .recording: return .accentColor
        case .error: return .red
        case .stale, .dfuDeclared: return .orange
        default: return .secondary
        }
    }
}
