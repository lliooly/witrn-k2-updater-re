import SwiftUI
import AppKit
import K2Core

extension DialElement {
    var swiftColor: Color {
        Color(.sRGB, red: Double((color >> 16) & 255) / 255, green: Double((color >> 8) & 255) / 255,
              blue: Double(color & 255) / 255, opacity: Double(color >> 24) / 255)
    }
    var previewText: String {
        ["5.1234 V", "1.2345 A", "6.320 W", "00:12:34", "D+ 0.60", "D− 0.60", "26.5°C", "PD 20V", "QC 3.0",
         "CC1 1.20", "CC2 0.00", "V5.8", "60 FPS", "➜", "↻", "0.123 Wh", "PD"][id]
    }
    var previewFont: Font { .system(size: CGFloat(isIcon ? 22 : fontHeight) * 0.77, weight: .medium, design: .monospaced) }
    var previewY: CGFloat { CGFloat(y) + (isIcon ? 0 : CGFloat(fontHeight)) }
}

struct DialCanvas: View {
    @ObservedObject var picture: PictureStore
    let scale: Double
    @State private var dragOrigin: DialElement?
    @State private var focusRequest = UUID()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if let image = picture.project.background?.cgImage {
                Image(decorative: image, scale: 1).resizable().frame(width: 240, height: 240)
            }
            ForEach(picture.project.layout.elements.filter { $0.enabled == 1 }) { element in
                Text(sample(element)).font(element.previewFont).foregroundStyle(element.swiftColor)
                    .fixedSize().padding(2)
                    .overlay { if picture.selectedElement == element.id { Rectangle().stroke(.white, style: StrokeStyle(lineWidth: 0.7, dash: [3, 2])) } }
                    .offset(x: CGFloat(element.x) - 2, y: element.previewY - 2)
                    .onTapGesture { picture.selectedElement = element.id; focusRequest = UUID() }
                    .gesture(DragGesture(minimumDistance: 2).onChanged { value in
                        if dragOrigin == nil {
                            picture.selectedElement = element.id; dragOrigin = element; picture.beginGesture(); focusRequest = UUID()
                        }
                        guard let origin = dragOrigin else { return }
                        picture.updateElement {
                            // SwiftUI already supplies translation in the scaled view's local coordinates.
                            $0.x = Int16(clamping: Int(origin.x) + Int(value.translation.width.rounded()))
                            $0.y = Int16(clamping: Int(origin.y) + Int(value.translation.height.rounded()))
                        }
                    }.onEnded { _ in dragOrigin = nil; picture.endGesture() })
            }
        }
        .frame(width: 240, height: 240).clipped()
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: 240 * scale, height: 240 * scale, alignment: .topLeading)
        .overlay(Rectangle().stroke(.secondary.opacity(0.35), lineWidth: 1))
        .background(CanvasKeyboard(focusRequest: focusRequest) { dx, dy in
            picture.updateElement {
                $0.x = Int16(clamping: Int($0.x) + dx)
                $0.y = Int16(clamping: Int($0.y) + dy)
            }
        })
        .accessibilityLabel("K2 表盘预览，示例读数")
    }
    private func sample(_ element: DialElement) -> String {
        guard let index = element.precisionIndex else { return element.previewText }
        let digits = picture.project.layout.precision(index)
        let values = [5.1234, 1.2345, 6.32, 0.6, 0.6, 1.2, 0.0, 0.123]
        let suffix = [" V", " A", " W", "", "", "", "", " Wh"][index]
        let prefix = ["", "", "", "D+ ", "D− ", "CC1 ", "CC2 ", ""][index]
        return prefix + String(format: "%.*f", digits, values[index]) + suffix
    }
}
