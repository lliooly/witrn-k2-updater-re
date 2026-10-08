import SwiftUI
import K2Core

struct ImageCropSheet: View {
    let item: ImageImport
    @ObservedObject var picture: PictureStore
    @State private var fit: ImageFit = .crop
    @State private var zoom = 1.0
    @State private var x = 0.0
    @State private var y = 0.0
    @State private var converted: PixelImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("准备\(item.kind.title)").font(.title2).fontWeight(.semibold)
            Text("\(item.source.width) × \(item.source.height) → \(item.kind.dimension) × \(item.kind.dimension)").foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 24) {
                if let image = converted?.cgImage {
                    Image(decorative: image, scale: 1).resizable().interpolation(.none)
                        .frame(width: 300, height: 300).background(.black)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Picker("处理方式", selection: $fit) { ForEach(ImageFit.allCases) { Text($0.rawValue).tag($0) } }
                    if fit == .crop {
                        Text("放大 \(zoom, specifier: "%.1f")×"); Slider(value: $zoom, in: 1...4)
                        Text("水平位置"); Slider(value: $x, in: -1...1)
                        Text("垂直位置"); Slider(value: $y, in: -1...1)
                    }
                    Text("空白与透明区域填充黑色。写入时转换为设备的 RGB565 色彩。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(width: 230)
            }
            HStack { Button("取消") { picture.imageImport = nil }.keyboardShortcut(.cancelAction); Spacer()
                Button("使用图片") { if let converted { picture.applyImage(converted, kind: item.kind) } }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(converted == nil)
            }
        }.padding(24).onAppear(perform: update)
        .onChange(of: fit) { _ in update() }.onChange(of: zoom) { _ in update() }
        .onChange(of: x) { _ in update() }.onChange(of: y) { _ in update() }
    }
    private func update() {
        do { converted = try PictureImages.convert(item.source, kind: item.kind, fit: fit, zoom: zoom, x: x, y: y) }
        catch { converted = nil; picture.error = error.localizedDescription }
    }
}
