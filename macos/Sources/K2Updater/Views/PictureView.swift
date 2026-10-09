import SwiftUI
import K2Core
import UniformTypeIdentifiers

struct PictureView: View {
    @ObservedObject var picture: PictureStore
    @ObservedObject var store: UpdaterStore
    let startup: Bool
    @SceneStorage("dialPreviewScale") private var scale = 1.5
    @State private var writeIntent: ResourceWriteIntent?
    @State private var dropTarget = false
    var body: some View {
        VStack(spacing: 0) {
            deviceControls.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            ScrollView {
                Group { if startup { startupEditor } else { dialEditor } }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .disabled(store.isBusy)
        .sheet(item: $picture.imageImport) { ImageCropSheet(item: $0, picture: picture) }
        .alert("\(writeIntent?.restoring == true ? "恢复" : "写入")\(writeIntent?.kind.title ?? "资源")？", isPresented: Binding(get: { writeIntent != nil }, set: { if !$0 { writeIntent = nil } })) {
            Button("取消", role: .cancel) { writeIntent = nil }
            Button("备份并\(writeIntent?.restoring == true ? "恢复" : "写入")") { if let intent = writeIntent { store.writeResource(intent) }; writeIntent = nil }
        } message: {
            Text("先读取目标资源的完整扇区两遍并保存备份，再擦除、写入并完整读回校验。仅操作\(writeIntent?.kind.title ?? "资源")。期间请保持连接")
        }
        .alert("文件操作失败", isPresented: Binding(get: { picture.error != nil }, set: { if !$0 { picture.error = nil } })) {
            Button("好", role: .cancel) { picture.error = nil }
        } message: { Text(picture.error ?? "") }
        .onDrop(of: [.fileURL], isTargeted: $dropTarget, perform: acceptDrop)
        .overlay { if dropTarget { RoundedRectangle(cornerRadius: 8).stroke(.blue, lineWidth: 2).allowsHitTesting(false) } }
    }
    private var deviceControls: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("设备操作")
                .font(.headline)

            if !startup {
                VStack(alignment: .leading, spacing: 20) {
                    resourceButtons(.layout)
                    Divider()
                    resourceButtons(.background)
                }
            } else {
                resourceButtons(.startup)
            }

            if !store.canUseResources { ResourceAvailabilityHint(store: store) }

            Text("⚠ " + (startup ? "每次写入后重新进入 DFU，再进行其他操作" : "背景和布局分别写入，每次完成后重新进入 DFU"))
                .font(.callout)
                .foregroundStyle(.red)
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private var dialEditor: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                dialPreview.frame(minWidth: 310, idealWidth: 352, maxWidth: .infinity)
                DialElementTable(picture: picture).fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 20) {
                dialPreview
                DialElementTable(picture: picture)
            }
        }
    }
    private var dialPreview: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Label("240 × 240", systemImage: "viewfinder").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Picker("缩放", selection: $scale) {
                    Text("100%").tag(1.0)
                    Text("150%").tag(1.5)
                    Text("200%").tag(2.0)
                }.frame(width: 140)
            }
            ScrollView([.horizontal, .vertical]) {
                DialCanvas(picture: picture, scale: scale).padding(6)
            }.frame(minHeight: 390, idealHeight: 400)
            Text("点击选择，拖动定位，方向键微调 1 像素")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button { picture.chooseImage(.background) } label: {
                    Label("导入背景", systemImage: "photo.badge.plus")
                }.buttonStyle(.borderedProminent)
                Menu {
                    Button { picture.edit { $0.background = nil } } label: {
                        Label("移除背景", systemImage: "trash")
                    }.disabled(picture.project.background == nil)
                    Button { picture.export(.background) } label: {
                        Label("导出 BMP", systemImage: "square.and.arrow.up")
                    }.disabled(picture.project.background == nil)
                } label: {
                    Label("背景操作", systemImage: "ellipsis.circle")
                }
                Spacer()
            }
        }.frame(maxWidth: .infinity)
    }
    private var startupEditor: some View {
        HStack(alignment: .top, spacing: 24) {
            startupPreview
            startupImageActions.frame(minWidth: 200)
        }.padding(.vertical, 12)
    }
    private var startupPreview: some View {
        ZStack {
            Color.black
            if let image = picture.project.startup?.cgImage { Image(decorative: image, scale: 1).resizable().interpolation(.none) }
            else { Text("导入一张开机图").foregroundStyle(.white.opacity(0.65)) }
        }.frame(width: 352.5, height: 352.5)
    }
    private var startupImageActions: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("235 × 235 像素").font(.title3.weight(.semibold))
                Text("支持 BMP、PNG 和 JPEG。导入时调整裁剪或缩放，确认后保存到工程").foregroundStyle(.secondary).font(.callout)
            }
            Button { picture.chooseImage(.startup) } label: {
                Label(picture.project.startup == nil ? "导入图片" : "替换图片", systemImage: "photo.badge.plus")
            }.buttonStyle(.borderedProminent).controlSize(.large)
            Menu {
                Button { picture.export(.startup) } label: {
                    Label("导出 BMP", systemImage: "square.and.arrow.up")
                }.disabled(picture.project.startup == nil)
                Button { picture.edit { $0.startup = nil } } label: {
                    Label("移除图片", systemImage: "trash")
                }.disabled(picture.project.startup == nil)
            } label: {
                Label("图片操作", systemImage: "ellipsis.circle")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func resourceButtons(_ kind: PictureResource) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind.title)
                .font(.subheadline)
                .fontWeight(.medium)
            HStack(spacing: 10) {
                Button("读取") {
                    store.readResource(kind) { picture.acceptRead($0, kind: $1) }
                }
                .disabled(!store.canUseResources)

                Button("写入") {
                    do {
                        writeIntent = ResourceWriteIntent(
                            kind: kind,
                            data: try picture.resourceData(kind),
                            manifest: nil,
                            manifestHash: nil
                        )
                    }
                    catch { picture.error = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.canUseResources ||
                         (kind == .background && picture.project.background == nil) ||
                         (kind == .startup && picture.project.startup == nil))
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
