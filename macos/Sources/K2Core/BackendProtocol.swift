import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let values) = self { return values[key] }
        return nil
    }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    public func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        try WireCodec.decoder.decode(type, from: JSONEncoder().encode(self))
    }
}

public enum BackendOperation: String, Codable, Sendable {
    case devices, inspect, probe, backup, upgrade
    case resourceRead = "resource-read", resourceWrite = "resource-write", resourceRestore = "resource-restore"
    public var canCancel: Bool { !isWrite }
    public var isWrite: Bool { self == .upgrade || self == .resourceWrite || self == .resourceRestore }
}

public struct BackendRequest: Encodable, Sendable {
    public var id = UUID().uuidString
    public var operation: BackendOperation
    public let simulation = false
    public var dataDirectory: String
    public var firmwarePath: String?
    public var firmwareSha256: String?
    public var devicePathHex: String?
    public var deviceSerial: String?
    public var deviceInfoSha256: String?
    public var dfuConfirmed = false
    public var confirmed = false
    public var resourceKind: String?
    public var resourcePath: String?
    public var resourceSha256: String?
    public var restoreManifestPath: String?
    public var restoreManifestSha256: String?

    public init(operation: BackendOperation, dataDirectory: String) {
        self.operation = operation; self.dataDirectory = dataDirectory
    }
}

public struct BackendEvent: Decodable, Sendable {
    public let schema: Int
    public let id: String
    public let operation: String
    public let event: String
    public let stage: String?
    public let current: Int?
    public let total: Int?
    public let message: String?
    public let cancelled: Bool?
    public let trace: String?
    public let backup: String?
    public let identity: JSONValue?
    public let device: JSONValue?
    public let value: JSONValue?
}

public enum WireCodec {
    public static var decoder: JSONDecoder {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase; return d
    }
    public static func requestData(_ request: BackendRequest) throws -> Data {
        let e = JSONEncoder(); e.keyEncodingStrategy = .convertToSnakeCase
        var data = try e.encode(request); data.append(10); return data
    }
}

public enum WireError: LocalizedError {
    case oversized, wrongSchema, incomplete
    public var errorDescription: String? {
        switch self {
        case .oversized: return "后台消息过大"
        case .wrongSchema: return "后台通信版本不匹配"
        case .incomplete: return "后台消息未完整接收"
        }
    }
}

public final class EventLineDecoder: @unchecked Sendable {
    private var pending = Data()
    private let lock = NSLock()
    public init() {}
    public func feed(_ data: Data) throws -> [BackendEvent] {
        lock.lock(); defer { lock.unlock() }
        pending.append(data)
        guard pending.count <= 1_048_576 else { throw WireError.oversized }
        var events: [BackendEvent] = []
        while let newline = pending.firstIndex(of: 10) {
            let line = Data(pending[..<newline])
            pending.removeSubrange(...newline)
            if line.isEmpty { continue }
            let event = try WireCodec.decoder.decode(BackendEvent.self, from: line)
            guard event.schema == 1 else { throw WireError.wrongSchema }
            events.append(event)
        }
        return events
    }
    public func finish() throws {
        lock.lock(); defer { lock.unlock() }
        guard pending.isEmpty else { throw WireError.incomplete }
    }
}
