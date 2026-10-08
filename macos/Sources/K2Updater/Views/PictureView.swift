import SwiftUI
import K2Core
import UniformTypeIdentifiers

struct PictureView: View {
    @ObservedObject var picture: PictureStore
    @ObservedObject var store: UpdaterStore
    let startup: Bool
    @State private var scale = 1.5
    @State private var writeIntent: ResourceWriteIntent?
    @State private var dropTarget = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(startup ? "开机图" : "表盘编辑器").font(.title2).fontWeight(.semibold)
                    Text((picture.projectURL?.lastPathComponent ?? "未命名工程") + (picture.dirty ? " · 已修改" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("打开工程 / .pic…") { picture.open() }
                Button("保存工程") { picture.save() }
            }
            if startup { startupEditor } else { dialEditor }
            Divider()
            HStack {
                if !startup { resourceButtons(.layout); Spacer(); resourceButtons(.background) }
                else { resourceButtons(.startup); Spacer() }
            }
            Text(startup ? "每次写入后重新进入 DFU，再进行其他操作。" : "背景和布局分别写入，每次完成后重新进入 DFU。最后在 K2 设置 → 6 主题屏开关中开启表盘。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .disabled(store.isBusy)
        .sheet(item: $picture.imageImport) { ImageCropSheet(item: $0, picture: picture) }
        .alert("\(writeIntent?.restoring == true ? "恢复" : "写入")\(writeIntent?.kind.title ?? "资源")？", isPresented: Binding(get: { writeIntent != nil }, set: { if !$0 { writeIntent = nil } })) {
            Button("取消", role: .cancel) { writeIntent = nil }
            Button("备份并\(writeIntent?.restoring == true ? "恢复" : "写入")") { if let intent = writeIntent { store.writeResource(intent) }; writeIntent = nil }
        } message: {
            Text("先读取目标资源的完整扇区两遍并保存备份，再擦除、写入并完整读回校验。仅操作\(writeIntent?.kind.title ?? "资源")。期间请保持连接。")
        }
        .alert("文件操作失败", isPresented: Binding(get: { picture.error != nil }, set: { if !$0 { picture.error = nil } })) {
            Button("好", role: .cancel) { picture.error = nil }
        } message: { Text(picture.error ?? "") }
        .onDrop(of: [.fileURL], isTargeted: $dropTarget, perform: acceptDrop)
        .overlay { if dropTarget { RoundedRectangle(cornerRadius: 8).stroke(.blue, lineWidth: 2).allowsHitTesting(false) } }
    }
    private var dialEditor: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("240 × 240").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Picker("缩放", selection: $scale) { Text("100%").tag(1.0); Text("150%").tag(1.5); Text("200%").tag(2.0) }.frame(width: 130)
                }
                ScrollView([.horizontal, .vertical]) { DialCanvas(picture: picture, scale: scale).padding(4) }
                    .frame(minHeight: 375, idealHeight: 390)
                Text("示例读数 · 字体和基线预览与实机可能不同\n点击选择，拖动定位，方向键微调 1 像素。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("导入背景…") { picture.chooseImage(.background) }
                    Button("移除背景") { picture.edit { $0.background = nil } }.disabled(picture.project.background == nil)
                    Spacer()
                    Menu("导出") {
                        Button("布局 .pic…") { picture.export(.layout) }
                        Button("背景 BMP…") { picture.export(.background) }.disabled(picture.project.background == nil)
                    }.fixedSize()
                }
            }.frame(maxWidth: .infinity)
            ElementInspector(picture: picture)
        }
    }
    private var startupEditor: some View {
        HStack(alignment: .top, spacing: 30) {
            ZStack {
                Color.black
                if let image = picture.project.startup?.cgImage { Image(decorative: image, scale: 1).resizable().interpolation(.none) }
                else { Text("导入一张开机图").foregroundStyle(.white.opacity(0.65)) }
            }.frame(width: 352.5, height: 352.5)
            VStack(alignment: .leading, spacing: 16) {
                Text("235 × 235 像素").font(.headline)
                Text("支持 BMP、PNG 和 JPEG。导入时调整裁剪或缩放，确认后保存到工程。") .foregroundStyle(.secondary)
                Button("导入图片…") { picture.chooseImage(.startup) }
                Button("导出 BMP…") { picture.export(.startup) }.disabled(picture.project.startup == nil)
                Button("移除图片") { picture.edit { $0.startup = nil } }.disabled(picture.project.startup == nil)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 12)
    }
    private func resourceButtons(_ kind: PictureResource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind.title).font(.headline)
            HStack {
                Button("读取并备份") { store.readResource(kind) { picture.acceptRead($0, kind: $1) } }.disabled(!store.canUseResources)
                Button("写入\(kind.title)") {
                    do { writeIntent = ResourceWriteIntent(kind: kind, data: try picture.resourceData(kind), manifest: nil, manifestHash: nil) }
                    catch { picture.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).disabled(!store.canUseResources || (kind == .background && picture.project.background == nil) || (kind == .startup && picture.project.startup == nil))
            }
        }
    }
    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !store.isBusy, let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                guard !store.isBusy else { return }
                if ["pic", "k2project"].contains(url.pathExtension.lowercased()) { picture.open(url) }
                else if ["bmp", "png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()) { picture.importImage(url, kind: startup ? .startup : .background) }
                else { picture.error = "支持 .pic、.k2project、BMP、PNG 或 JPEG 文件" }
            }
        }
        return true
    }
}
