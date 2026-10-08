import SwiftUI
import AppKit
import K2Core

struct DialElementTable: View {
    @ObservedObject var picture: PictureStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("表盘元素").font(.title3.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    Text("元素").frame(width: 74, alignment: .leading)
                    Text("显示").frame(width: 40)
                    Text("X").frame(width: 64)
                    Text("Y").frame(width: 64)
                    Text("颜色").frame(width: 36)
                    Text("字号").frame(width: 80)
                    Text("小数位").frame(width: 64)
                }.font(.callout).foregroundStyle(.secondary)
                ForEach(picture.project.layout.elements) { element in
                    DialElementRow(picture: picture, elementID: element.id)
                }
            }.controlSize(.small)
            Text("点击元素名称可在画布中选中。X / Y 为设备坐标；图标不设置字号，没有小数位的元素显示 —")
                .font(.callout).foregroundStyle(.secondary).frame(maxWidth: 440, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(14).background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct DialElementRow: View {
    @ObservedObject var picture: PictureStore
    let elementID: Int
    private var editing: DialElementEditing { DialElementEditing(picture: picture, elementID: elementID) }
    private var element: DialElement { editing.element }

    var body: some View {
        GridRow {
            Button { picture.selectedElement = elementID } label: {
                Text(element.title).fontWeight(picture.selectedElement == elementID ? .semibold : .regular)
                    .foregroundStyle(picture.selectedElement == elementID ? Color.accentColor : Color.primary)
                    .frame(width: 74, alignment: .leading)
            }.buttonStyle(.plain).help("在画布中选中\(element.title)")
            Toggle("显示\(element.title)", isOn: Binding(get: { element.enabled == 1 }, set: { editing.setVisible($0) }))
                .toggleStyle(.switch).labelsHidden().frame(width: 40)
            DialCoordinateField(picture: picture, elementID: elementID, xAxis: true).frame(width: 64)
            DialCoordinateField(picture: picture, elementID: elementID, xAxis: false).frame(width: 64)
            ColorPicker("\(element.title)颜色", selection: Binding(get: { element.swiftColor }, set: { editing.setColor($0) }), supportsOpacity: true)
                .labelsHidden().frame(width: 36)
            if element.isIcon {
                Text("—").foregroundStyle(.secondary).frame(width: 80)
                    .help("图标不设置字号")
            } else {
                Picker("\(element.title)字号", selection: Binding(get: { Int(element.font) }, set: { editing.setFont($0) })) {
                    ForEach(0..<DialElement.fontTitles.count, id: \.self) { Text(DialElement.fontTitles[$0]).tag($0) }
                    if Int(element.font) >= DialElement.fontTitles.count {
                        Text("未知 \(element.font)").tag(Int(element.font)).disabled(true)
                    }
                }.labelsHidden().frame(width: 80)
            }
            if let index = element.precisionIndex {
                let current = picture.project.layout.precision(index)
                Picker("\(element.title)小数位", selection: Binding(get: { picture.project.layout.precision(index) }, set: { editing.setPrecision($0) })) {
                    ForEach(Array(element.precisionRange), id: \.self) { Text(String($0)).tag($0) }
                    if !element.precisionRange.contains(current) { Text(String(current)).tag(current).disabled(true) }
                }.labelsHidden().frame(width: 64)
            } else {
                Text("—").foregroundStyle(.secondary).frame(width: 64)
                    .help("此元素没有小数位设置")
            }
        }.font(.callout)
    }
}

/// Edits always target the row's fixed ID, even when a different canvas item is selected.
@MainActor
struct DialElementEditing {
    let picture: PictureStore
    let elementID: Int
    var element: DialElement { picture.project.layout.element(elementID) }

    func setVisible(_ visible: Bool) {
        update {
            $0.enabled = visible ? 1 : 0
            if $0.font > 6 && !$0.isIcon { $0.font = 1 }
        }
    }
    func setFont(_ font: Int) {
        guard !element.isIcon, DialElement.fontTitles.indices.contains(font) else { return }
        update { $0.font = UInt8(font) }
    }
    func setColor(_ color: Color) {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
        update {
            $0.color = UInt32((c.alphaComponent * 255).rounded()) << 24 |
                UInt32((c.redComponent * 255).rounded()) << 16 |
                UInt32((c.greenComponent * 255).rounded()) << 8 |
                UInt32((c.blueComponent * 255).rounded())
        }
    }
    func setPrecision(_ value: Int) {
        guard let index = element.precisionIndex, element.precisionRange.contains(value) else { return }
        picture.selectedElement = elementID
        picture.edit { $0.layout.setPrecision(index, value: value) }
    }
    func setCoordinate(_ value: Int, xAxis: Bool, group: UUID) {
        picture.edit(coalescing: group) {
            var element = $0.layout.element(elementID)
            if xAxis { element.x = Int16(clamping: value) } else { element.y = Int16(clamping: value) }
            $0.layout.update(element)
        }
    }
    private func update(_ change: (inout DialElement) -> Void) {
        picture.selectedElement = elementID
        picture.updateElement(change)
    }
}

private struct DialCoordinateField: View {
    @ObservedObject var picture: PictureStore
    let elementID: Int
    let xAxis: Bool
    @State private var text = ""
    @State private var group = UUID()
    @FocusState private var focused: Bool
    private var editing: DialElementEditing { DialElementEditing(picture: picture, elementID: elementID) }
    private var value: Int16 { xAxis ? editing.element.x : editing.element.y }

    var body: some View {
        TextField(xAxis ? "X" : "Y", text: $text)
            .textFieldStyle(.roundedBorder).font(.callout.monospacedDigit())
            .accessibilityLabel("\(editing.element.title)\(xAxis ? "X" : "Y")坐标")
            .focused($focused).onAppear { reset() }
            .onSubmit { commit(); focused = false }
            .onChange(of: text) { _ in if focused { commit() } }
            .onChange(of: focused) { active in
                if active { group = UUID(); picture.selectedElement = elementID } else { reset() }
            }
            .onChange(of: value) { _ in reset() }
            .onChange(of: picture.selectedElement) { next in
                if focused && next != elementID { commit(); focused = false }
            }
            .help("\(editing.element.title)的设备坐标，范围 −32768 到 32767。")
    }
    private func reset() { text = String(value) }
    private func commit() {
        guard let number = Int(text) else { return }
        editing.setCoordinate(number, xAxis: xAxis, group: group)
    }
}
