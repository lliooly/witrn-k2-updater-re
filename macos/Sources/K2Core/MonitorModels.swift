import Foundation

public struct MonitorSample: Decodable, Identifiable, Sendable {
    public let time: Double
    public let voltage: Double
    public let current: Double
    public let power: Double
    public let signedPower: Double
    public let tempIn: Double?
    public let tempOut: Double?
    public let dp: Double?
    public let dn: Double?
    public let ah: Double?
    public let wh: Double?
    public let recordSeconds: Int?
    public let uptime: Int?
    public let group: Int?
    public let segment: Int
    public var id: String { "\(segment):\(time)" }
    /// Query points are ordered by time. Preserve the old nearest-point/tie
    /// behavior without scanning the whole plotted series on every mouse move.
    public static func nearest(in points: [MonitorSample], to time: Double) -> MonitorSample? {
        guard time.isFinite, !points.isEmpty else { return nil }
        func lowerBound(_ target: Double) -> Int {
            var low = 0, high = points.count
            while low < high {
                let middle = low + (high - low) / 2
                if points[middle].time < target { low = middle + 1 }
                else { high = middle }
            }
            return low
        }
        let next = lowerBound(time)
        let index: Int
        if next == 0 { index = 0 }
        else if next == points.count { index = next - 1 }
        else { index = time - points[next - 1].time <= points[next].time - time ? next - 1 : next }
        return points[lowerBound(points[index].time)]
    }
    public func value(_ channel: MonitorChannel) -> Double? {
        switch channel {
        case .voltage: return voltage
        case .current: return current
        case .power: return power
        case .tempIn: return tempIn
        case .tempOut: return tempOut
        case .dp: return dp
        case .dn: return dn
        }
    }
}

public enum MonitorChannel: String, CaseIterable, Identifiable, Sendable {
    case voltage, current, power, tempIn = "temp_in", tempOut = "temp_out", dp, dn
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .voltage: return "电压"
        case .current: return "电流"
        case .power: return "功率"
        case .tempIn: return "内部温度"
        case .tempOut: return "外部温度"
        case .dp: return "D+"
        case .dn: return "D−"
        }
    }
    public var unit: String {
        switch self {
        case .voltage, .dp, .dn: return "V"
        case .current: return "A"
        case .power: return "W"
        case .tempIn, .tempOut: return "°C"
        }
    }
}

public struct MonitorStatus: Decodable, Sendable {
    public let recording: Bool
    public let paused: Bool
    public let recordPath: String?
    public let recordCount: Int
    public let previewPath: String?
    public let latest: MonitorSample?
    public let received: Int?
    public let receiveRate: Double?
    public let elapsed: Double?
    public let stale: Bool?
    public let invalid: Int?
    public let checksumMatches: Int?
    public let notice: String?
    public let controlAck: String?
}

public struct MonitorRecord: Decodable, Identifiable, Sendable {
    public let path: String
    public let count: Int
    public let start: Double?
    public let end: Double?
    public let metadata: [String: String]
    public var id: String { path }
    public var unfinished: Bool { metadata["closed"] != "1" }
}

public struct MonitorQuery: Decodable, Sendable {
    public let path: String
    public let count: Int
    public let start: Double?
    public let end: Double?
    public let rangeStart: Double?
    public let rangeEnd: Double?
    public let points: [MonitorSample]
    public let statistics: MonitorStatistics?
}

public struct MonitorChannelStatistics: Decodable, Sendable {
    public let min: Double?
    public let max: Double?
    public let average: Double?
    public let coverage: Double
}

public struct MonitorStatistics: Decodable, Sendable {
    public let count: Int
    public let span: Double
    public let coverage: Double
    public let channels: [String: MonitorChannelStatistics]
    public let ahPositive: Double
    public let ahNegative: Double
    public let ahAbsolute: Double
    public let ahNet: Double
    public let whPositive: Double
    public let whNegative: Double
    public let whAbsolute: Double
    public let whNet: Double
    public let percentages: [String: Double?]
}

public enum MonitorFormat {
    public static func number(_ value: Double?, digits: Int = 3) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.*f", digits, value)
    }
    public static func elapsed(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max / 1000) else { return "—" }
        let ms = Int((seconds * 1000).rounded())
        let day = ms / 86_400_000
        return (day > 0 ? "\(day)." : "") + String(format: "%02d:%02d:%02d.%03d", ms / 3_600_000 % 24, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }
}
