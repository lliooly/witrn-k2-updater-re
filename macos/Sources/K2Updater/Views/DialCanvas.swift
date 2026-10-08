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

struct ElementInspector: View {
    @ObservedObject var picture: PictureStore
    var body: some View {
        Form {
            Section {
                Picker("元素", selection: $picture.selectedElement) {
                    ForEach(picture.project.layout.elements) { Text($0.title).tag($0.id) }
                }
                Toggle("显示", isOn: Binding(get: { picture.element.enabled == 1 }, set: { enabled in picture.updateElement { $0.enabled = enabled ? 1 : 0; if $0.font > 6 && !$0.isIcon { $0.font = 1 } } }))
                HStack {
                    CoordinateField(picture: picture, xAxis: true)
                    CoordinateField(picture: picture, xAxis: false)
                }
                Text("Y 为设备坐标；拖动预览可调整位置。") .font(.caption).foregroundStyle(.secondary)
                ColorPicker("颜色", selection: Binding(get: { picture.element.swiftColor }, set: { color in
                    guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
                    picture.updateElement { $0.color = UInt32((c.alphaComponent * 255).rounded()) << 24 |
                        UInt32((c.redComponent * 255).rounded()) << 16 | UInt32((c.greenComponent * 255).rounded()) << 8 |
                        UInt32((c.blueComponent * 255).rounded()) }
                }), supportsOpacity: true)
                if !picture.element.isIcon {
                    Picker("字号", selection: Binding(get: { Int(picture.element.font) }, set: { size in picture.updateElement { $0.font = UInt8(size) } })) {
                        ForEach(0..<7) { Text(DialElement.fontTitles[$0]).tag($0) }
                    }
                }
                if let index = picture.element.precisionIndex {
                    Stepper("小数位：\(picture.project.layout.precision(index))", value: Binding(get: { picture.project.layout.precision(index) }, set: { value in picture.edit { $0.layout.setPrecision(index, value: value) } }), in: picture.element.precisionRange)
                }
            } header: { Text("\(picture.element.title)属性") }
        }.formStyle(.grouped).frame(width: 265)
    }
}

private struct CoordinateField: View {
    @ObservedObject var picture: PictureStore
    let xAxis: Bool
    @State private var text = ""
    @State private var editingID = 0
    @State private var group = UUID()
    @FocusState private var focused: Bool
    private var value: Int16 { xAxis ? picture.element.x : picture.element.y }
    var body: some View {
        TextField(xAxis ? "X" : "Y", text: $text)
            .focused($focused).onAppear { reset() }
            .onSubmit { commit(); focused = false }
            .onChange(of: text) { _ in if focused { commit() } }
            .onChange(of: focused) { active in
                if active { editingID = picture.selectedElement; group = UUID() } else { reset() }
            }
            .onChange(of: value) { _ in if !focused || picture.selectedElement == editingID { reset() } }
            .onChange(of: picture.selectedElement) { _ in if focused { commit(); focused = false }; reset() }
            .help("设备坐标，范围 −32768 到 32767。")
    }
    private func reset() { text = String(value); if !focused { editingID = picture.selectedElement } }
    private func commit() {
        guard let number = Int(text) else { return }
        let id = editingID
        picture.edit(coalescing: group) {
            var element = $0.layout.element(id)
            if xAxis { element.x = Int16(clamping: number) } else { element.y = Int16(clamping: number) }
            $0.layout.update(element)
        }
    }
}
