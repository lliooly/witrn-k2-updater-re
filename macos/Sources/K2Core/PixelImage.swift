import Foundation

public struct PixelImage: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let rgba: Data

    public init(width: Int, height: Int, rgba: Data) throws {
        guard (1...4096).contains(width), (1...4096).contains(height), rgba.count == width * height * 4 else {
            throw PictureError.invalid("图片尺寸或像素数据无效")
        }
        self.width = width; self.height = height; self.rgba = rgba
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(width: c.decode(Int.self, forKey: .width), height: c.decode(Int.self, forKey: .height),
                      rgba: c.decode(Data.self, forKey: .rgba))
    }

    public func resourceData(_ kind: PictureResource) throws -> Data {
        guard kind != .layout, width == kind.dimension, height == kind.dimension else {
            throw PictureError.invalid("\(kind.title)必须是 \(kind.dimension) × \(kind.dimension)")
        }
        let pixels = [UInt8](rgba)
        var result = Data(PictureLayout.magic)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let a = Int(pixels[offset + 3])
            let r = UInt16(Int(pixels[offset]) * a / 255)
            let g = UInt16(Int(pixels[offset + 1]) * a / 255)
            let b = UInt16(Int(pixels[offset + 2]) * a / 255)
            let word = (r >> 3) << 11 | (g >> 2) << 5 | (b >> 3)
            result.append(UInt8(truncatingIfNeeded: word)); result.append(UInt8(truncatingIfNeeded: word >> 8))
        }
        result.append(contentsOf: PictureLayout.magic)
        return result
    }

    public init(resourceData: Data, kind: PictureResource) throws {
        let bytes = [UInt8](resourceData)
        guard kind != .layout, bytes.count == kind.size,
              Array(bytes.prefix(4)) == PictureLayout.magic, Array(bytes.suffix(4)) == PictureLayout.magic else {
            throw PictureError.invalid("设备图片数据无效或尚未设置")
        }
        var rgba = Data(capacity: kind.dimension * kind.dimension * 4)
        for offset in stride(from: 4, to: bytes.count - 4, by: 2) {
            let word = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
            let r = UInt8((word >> 11) & 31), g = UInt8((word >> 5) & 63), b = UInt8(word & 31)
            rgba.append(contentsOf: [(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2), 255])
        }
        try self.init(width: kind.dimension, height: kind.dimension, rgba: rgba)
    }

    public func bmpData() -> Data {
        // Bottom-up, 24-bit Windows BMP with padded rows.
        let stride = (width * 3 + 3) & ~3, size = 54 + stride * height
        var bytes = [UInt8](repeating: 0, count: size)
        func put(_ value: UInt32, _ position: Int, _ count: Int = 4) {
            for i in 0..<count { bytes[position + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) }
        }
        bytes[0] = 66; bytes[1] = 77
        put(UInt32(size), 2); put(54, 10); put(40, 14); put(UInt32(width), 18); put(UInt32(height), 22)
        put(1, 26, 2); put(24, 28, 2); put(UInt32(stride * height), 34)
        let source = [UInt8](rgba)
        for y in 0..<height { for x in 0..<width {
            let s = (y * width + x) * 4, p = 54 + (height - 1 - y) * stride + x * 3
            let a = Int(source[s + 3])
            bytes[p] = UInt8(Int(source[s + 2]) * a / 255)
            bytes[p + 1] = UInt8(Int(source[s + 1]) * a / 255)
            bytes[p + 2] = UInt8(Int(source[s]) * a / 255)
        } }
        return Data(bytes)
    }
}
