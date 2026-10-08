import Foundation
import CoreGraphics
import ImageIO

public enum ImageFit: String, CaseIterable, Identifiable {
    case crop = "裁剪填满", fit = "完整保留", stretch = "拉伸"
    public var id: String { rawValue }
}

public enum PictureImages {
    public static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 32768, height <= 32768 else {
            throw PictureError.invalid("无法读取图片或图片尺寸过大")
        }
        // ImageIO applies EXIF orientation and bounds decoded memory.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 4096]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PictureError.invalid("无法解码图片")
        }
        return image
    }

    public static func convert(_ image: CGImage, kind: PictureResource, fit: ImageFit,
                        zoom: Double = 1, x: Double = 0, y: Double = 0) throws -> PixelImage {
        guard kind.dimension > 0 else { throw PictureError.invalid("此资源不是图片") }
        let n = kind.dimension, w = Double(image.width), h = Double(image.height)
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        let made = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8,
                bytesPerRow: n * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.setFillColor(CGColor(gray: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: n, height: n))
            context.interpolationQuality = .high
            let size = Double(n)
            let scale = fit == .crop ? max(size / w, size / h) * zoom : min(size / w, size / h)
            let dw = fit == .stretch ? size : w * scale, dh = fit == .stretch ? size : h * scale
            let dx = (size - dw) / 2 + (fit == .crop ? x * (dw - size) / 2 : 0)
            let dy = (size - dh) / 2 + (fit == .crop ? y * (dh - size) / 2 : 0)
            context.draw(image, in: CGRect(x: dx, y: dy, width: dw, height: dh))
            return true
        }
        guard made else { throw PictureError.invalid("无法处理图片") }
        return try PixelImage(width: n, height: n, rgba: Data(bytes))
    }
}

extension PixelImage {
    public var cgImage: CGImage? {
        guard let provider = CGDataProvider(data: rgba as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
