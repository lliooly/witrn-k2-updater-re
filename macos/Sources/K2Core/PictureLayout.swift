import Foundation

public enum PictureError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

public enum PictureResource: String, Codable, CaseIterable, Sendable {
    case layout, background, startup, emark
    case emarkCopy = "emark-copy"
    public var title: String {
        switch self { case .layout: return "表盘布局"; case .background: return "表盘背景"; case .startup: return "开机图"; case .emark: return "E-Mark 配置集合"; case .emarkCopy: return "复制的 E-Mark" }
    }
    public var dimension: Int { self == .startup ? 235 : (self == .background ? 240 : 0) }
    public var size: Int { switch self { case .layout: return 400; case .emark: return 666; case .emarkCopy: return 66; default: return dimension * dimension * 2 + 8 } }
}

public struct DialElement: Identifiable, Equatable, Sendable {
    public let id: Int
    public var color: UInt32
    public var x: Int16
    public var y: Int16
    public var enabled: UInt8
    public var font: UInt8
    public var title: String { Self.titles[id] }
    public var isIcon: Bool { id == 13 || id == 14 }
    public var precisionIndex: Int? { [0: 0, 1: 1, 2: 2, 4: 3, 5: 4, 9: 5, 10: 6, 15: 7][id] }
    public var precisionRange: ClosedRange<Int> {
        switch precisionIndex { case 2, 7: return 3...7; case 3, 4, 5, 6: return 2...3; default: return 2...7 }
    }
    public var fontHeight: Int { Int(font) < Self.fontHeights.count ? Self.fontHeights[Int(font)] : 16 }
    public static let fontHeights = [11, 16, 21, 27, 40, 46, 58]
    public static let fontTitles = ["S7", "M12", "D15", "D18", "D28", "Bh36", "D36"]
    public static let titles = ["电压", "电流", "功率", "时间", "D+", "D−", "温度", "PD", "QC", "CC1", "CC2", "版本", "FPS", "方向箭头", "旋转图标", "Wh", "PD 标题"]
}

public struct PictureLayout: Codable, Equatable, Sendable {
    public private(set) var data: Data
    public static let magic: [UInt8] = [0x5a, 0xa5, 0x5a, 0xa5]

    public init(data: Data) throws {
        guard data.count == 400 else { throw PictureError.invalid(".pic 长度必须是 400 字节") }
        let bytes = [UInt8](data)
        guard Array(bytes[0..<4]) == Self.magic, Array(bytes[396..<400]) == Self.magic else {
            throw PictureError.invalid(".pic 头尾标记错误")
        }
        self.data = data
        for element in elements {
            guard element.enabled <= 1 else { throw PictureError.invalid("\(element.title)的显示开关无效") }
            guard element.isIcon || element.enabled == 0 || element.font <= 6 else {
                throw PictureError.invalid("\(element.title)的字号无效")
            }
        }
        guard bytes[224..<232].allSatisfy({ $0 <= 9 }) else { throw PictureError.invalid("数字精度超出支持范围") }
        for element in elements where element.enabled == 1 {
            if let index = element.precisionIndex, !element.precisionRange.contains(precision(index)) {
                throw PictureError.invalid("\(element.title)的小数位应为 \(element.precisionRange.lowerBound)…\(element.precisionRange.upperBound)")
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(data: c.decode(Data.self, forKey: .data))
    }

    public var elements: [DialElement] { (0..<17).map(element) }
    public func element(_ index: Int) -> DialElement {
        precondition((0..<17).contains(index))
        let b = [UInt8](data), p = 4 + index * 10
        let color = UInt32(b[p]) | UInt32(b[p + 1]) << 8 | UInt32(b[p + 2]) << 16 | UInt32(b[p + 3]) << 24
        let x = Int16(bitPattern: UInt16(b[p + 4]) | UInt16(b[p + 5]) << 8)
        let y = Int16(bitPattern: UInt16(b[p + 6]) | UInt16(b[p + 7]) << 8)
        return DialElement(id: index, color: color, x: x, y: y, enabled: b[p + 8], font: b[p + 9])
    }

    public mutating func update(_ value: DialElement) {
        guard (0..<17).contains(value.id) else { return }
        var b = [UInt8](data)
        let p = 4 + value.id * 10, x = UInt16(bitPattern: value.x), y = UInt16(bitPattern: value.y)
        for offset in 0..<4 { b[p + offset] = UInt8(truncatingIfNeeded: value.color >> (offset * 8)) }
        b[p + 4] = UInt8(truncatingIfNeeded: x); b[p + 5] = UInt8(truncatingIfNeeded: x >> 8)
        b[p + 6] = UInt8(truncatingIfNeeded: y); b[p + 7] = UInt8(truncatingIfNeeded: y >> 8)
        b[p + 8] = value.enabled; b[p + 9] = value.font
        data = Data(b)
    }

    public func precision(_ index: Int) -> Int { Int(data[224 + index]) }
    public mutating func setPrecision(_ index: Int, value: Int) {
        guard (0..<8).contains(index), (0...9).contains(value) else { return }
        data[224 + index] = UInt8(value)
    }

    public static var standard: PictureLayout {
        var bytes = [UInt8](repeating: 0, count: 400)
        bytes.replaceSubrange(0..<4, with: magic); bytes.replaceSubrange(396..<400, with: magic)
        var layout = try! PictureLayout(data: Data(bytes))
        // A new layout belongs to this app, not a copied vendor template.
        let positions: [(Int16, Int16)] = [(12, 0), (12, 48), (12, 96), (12, 164), (12, 164), (122, 164),
                                          (12, 192), (12, 144), (122, 144), (12, 186), (122, 186),
                                          (174, 210), (12, 210), (214, 12), (214, 42), (12, 138), (12, 144)]
        for index in 0..<17 {
            let font: UInt8 = index < 3 ? 4 : (index == 11 ? 0 : 1)
            layout.update(DialElement(id: index, color: 0xff66d5ea, x: positions[index].0, y: positions[index].1,
                                      enabled: [0, 1, 2, 4, 5, 11].contains(index) ? 1 : 0, font: font))
        }
        for (index, value) in [4, 4, 3, 2, 2, 2, 2, 3].enumerated() { layout.setPrecision(index, value: value) }
        return layout
    }
}
