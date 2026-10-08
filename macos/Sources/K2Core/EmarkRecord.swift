import Foundation

public struct EmarkField: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let offset: Int
    public let shift: Int
    public let width: Int
    public let options: [String]
    public var maximum: UInt32 { width == 32 ? .max : (1 << width) - 1 }
    public init(_ id: String, _ title: String, _ offset: Int, _ shift: Int, _ width: Int, _ options: [String] = []) {
        self.id = id; self.title = title; self.offset = offset; self.shift = shift; self.width = width; self.options = options
    }
    public static let identity: [EmarkField] = [
        .init("vid", "厂商 VID", 25, 0, 16),
        .init("connector", "连接类型", 25, 21, 2, ["兼容旧系统", "保留 1", "Type-C（编码 2）", "Type-C（编码 3）"]),
        .init("ufp", "UFP 类型", 25, 27, 3, ["不是线材", "保留 1", "保留 2", "无源线材", "有源线材", "保留 5", "VCONN 供电 USB 设备", "保留 7"]),
        .init("modal", "支持模式操作", 25, 26, 1, ["否", "是"]),
        .init("device", "作为设备", 25, 30, 1, ["否", "是"]),
        .init("host", "作为主机", 25, 31, 1, ["否", "是"]),
        .init("pid", "产品 PID", 33, 16, 16),
        .init("bcd", "设备 BCD 版本", 33, 0, 16),
        .init("cert", "认证标识 XID", 29, 0, 32)
    ]
    public static let cable: [EmarkField] = [
        .init("speed", "USB 速度", 37, 0, 3, ["USB 2.0", "USB 3.2 Gen 1", "USB 3.2 / USB4 Gen 2", "USB4 Gen 3", "USB4 Gen 4", "保留 5", "保留 6", "保留 7"]),
        .init("current", "电流能力", 37, 5, 2, ["未定义", "3 A", "5 A", "保留 3"]),
        .init("voltage", "最大电压", 37, 9, 2, ["20 V", "30 V", "40 V", "50 V"]),
        .init("termination", "端口类型", 37, 11, 2, ["无源，无 VCONN", "有源，有 VCONN", "保留 2", "保留 3"]),
        .init("latency", "延迟 / 长度等级", 37, 13, 4, ["未定义", "< 1 m", "1–2 m", "2–3 m", "3–4 m", "4–5 m", "5–6 m", "6–7 m", "> 7 m", "保留 9", "保留 10", "保留 11", "保留 12", "保留 13", "保留 14", "保留 15"]),
        .init("epr", "支持 EPR", 37, 17, 1, ["否", "是"]),
        .init("plug", "Type-C 插头类型", 37, 18, 2, ["保留 0", "保留 1", "公头", "母座"]),
        .init("version", "Cable VDO 版本", 37, 21, 3, ["1.0", "保留 1", "保留 2", "保留 3", "保留 4", "保留 5", "保留 6", "保留 7"]),
        .init("firmware", "固件版本", 37, 24, 4), .init("hardware", "硬件版本", 37, 28, 4)
    ]
    public static let rawTitles = ["Identity 消息头", "ID Header VDO", "Cert Stat VDO", "Product VDO", "Cable VDO", "Identity 扩展 VDO", "SVID 消息头", "SVID VDO 1", "SVID VDO 2", "Modes 消息头", "Modes VDO"]
}

public struct EmarkRecord: Equatable, Codable, Sendable {
    public static let size = 66
    public private(set) var data: Data
    public init(data: Data) throws {
        let b = [UInt8](data)
        guard b.count == Self.size else { throw PictureError.invalid(".wtemark 长度必须是 66 字节") }
        guard b[65] == Self.checksum(b) else { throw PictureError.invalid("E-Mark 配置校验失败") }
        guard b[..<19].contains(0) else { throw PictureError.invalid("E-Mark 名称缺少结束符") }
        guard [1, 2].contains(b[20]) else { throw PictureError.invalid("E-Mark PD 版本编码必须是 1（2.0）或 2（3.x）") }
        self.data = Data(b)
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self); try self.init(data: c.decode(Data.self, forKey: .data))
    }
    public var name: String { String(String.UnicodeScalarView(data.prefix(19).prefix(while: { $0 != 0 }).map { UnicodeScalar(Int($0))! })) }
    public mutating func setName(_ text: String) throws {
        let scalars = Array(text.unicodeScalars)
        guard scalars.count <= 18, scalars.allSatisfy({ $0.value > 0 && $0.value <= 255 }) else {
            throw PictureError.invalid("名称最多 18 个 Latin-1 字符；官方格式不支持中文名称")
        }
        var b = [UInt8](data); b.replaceSubrange(0..<19, with: scalars.map { UInt8($0.value) } + Array(repeating: 0, count: 19 - scalars.count))
        b[65] = Self.checksum(b); data = Data(b)
    }
    public var pdVersion: Int { Int(data[20]) }
    public var area: Int { Int(data[19]) }
    public mutating func setPDVersion(_ version: Int) throws {
        guard [1, 2].contains(version) else { throw PictureError.invalid("PD 版本无效") }; updateByte(20, UInt8(version))
    }
    public mutating func setArea(_ area: Int) throws {
        guard (0...255).contains(area) else { throw PictureError.invalid("配置区域必须为 0…255") }; updateByte(19, UInt8(area))
    }
    private mutating func updateByte(_ index: Int, _ value: UInt8) {
        var b = [UInt8](data); b[index] = value; b[65] = Self.checksum(b); data = Data(b)
    }
    public func word(_ offset: Int) -> UInt32 {
        precondition(offset >= 21 && offset <= 61 && (offset - 21) % 4 == 0)
        let b = [UInt8](data); return (0..<4).reduce(0) { $0 | UInt32(b[offset + $1]) << ($1 * 8) }
    }
    public mutating func setWord(_ offset: Int, _ value: UInt32) throws {
        guard offset >= 21, offset <= 61, (offset - 21) % 4 == 0 else { throw PictureError.invalid("VDO 偏移无效") }
        var b = [UInt8](data)
        for i in 0..<4 { b[offset + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) }
        b[65] = Self.checksum(b); data = Data(b)
    }
    public func value(_ field: EmarkField) -> UInt32 { (word(field.offset) >> field.shift) & field.maximum }
    public mutating func set(_ field: EmarkField, value: UInt32) throws {
        guard value <= field.maximum else { throw PictureError.invalid("\(field.title)超出范围") }
        let mask = field.maximum << field.shift
        try setWord(field.offset, (word(field.offset) & ~mask) | (value << field.shift))
    }
    private static func checksum(_ b: [UInt8]) -> UInt8 { UInt8(truncatingIfNeeded: b.prefix(65).reduce(0xA5) { $0 + Int($1) }) }
    public static var standard: EmarkRecord {
        var b = [UInt8](repeating: 0, count: size); b[20] = 2; b[65] = checksum(b)
        var r = try! EmarkRecord(data: Data(b)); try! r.setName("K2 configuration")
        for (id, value) in [("ufp", UInt32(3)), ("connector", 2), ("current", 2), ("voltage", 3), ("epr", 1), ("plug", 2), ("version", 0)] {
            if let f = (EmarkField.identity + EmarkField.cable).first(where: { $0.id == id }) { try! r.set(f, value: value) }
        }
        // Construct response headers independently from the vendor reset setters.
        try! r.setWord(21, 0xFF00A041)
        try! r.setWord(45, 0xFF00A042)
        try! r.setWord(57, 0x8087A043)
        return r
    }
}
