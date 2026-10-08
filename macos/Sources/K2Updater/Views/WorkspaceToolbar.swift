import SwiftUI

struct WorkspaceToolbar: View {
    let section: ToolSection
    @ObservedObject var store: UpdaterStore
    @ObservedObject var picture: PictureStore
    @ObservedObject var emark: EmarkStore
    private var editor: Bool { section == .dial || section == .startup || section == .emark }
    private var isEmark: Bool { section == .emark }
    private var dirty: Bool { isEmark ? emark.dirty || !emark.invalidFields.isEmpty : picture.dirty }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label(section.rawValue, systemImage: section.symbol).font(.headline)
                if editor {
                    Text((isEmark ? emark.projectURL?.lastPathComponent : picture.projectURL?.lastPathComponent) ?? "未命名工程")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(dirty ? "未保存更改" : "无未保存更改").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text(section == .monitor ? "实时曲线与采集记录" : "检查固件、备份并更新设备")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            if editor {
                Menu("文件") {
                    Button("新建工程") { if isEmark { emark.newProject() } else { picture.newProject() } }
                    Button("打开工程…") { if isEmark { emark.open() } else { picture.open() } }
                    Button("工程另存为…") { if isEmark { emark.save(asNew: true) } else { picture.save(asNew: true) } }
                    Divider()
                    if isEmark {
                        Button("导入 .wtemark…") { emark.importRecords() }.disabled(emark.bank.count >= 10 || !emark.invalidFields.isEmpty)
                        Button("导出选中配置…") { emark.export() }.disabled(emark.record == nil || !emark.invalidFields.isEmpty)
                    } else {
                        Button("导出布局 .pic…") { picture.export(.layout) }
                        Button("导出背景 BMP…") { picture.export(.background) }.disabled(picture.project.background == nil)
                        Button("导出开机图 BMP…") { picture.export(.startup) }.disabled(picture.project.startup == nil)
                    }
                }.fixedSize()
                Button("保存工程") { if isEmark { emark.save() } else { picture.save() } }
                Button { if isEmark { emark.undo() } else { picture.undo() } } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(isEmark ? !emark.undoAvailable : !picture.undoAvailable).help("撤销").accessibilityLabel("撤销")
                Button { if isEmark { emark.redo() } else { picture.redo() } } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(isEmark ? !emark.redoAvailable : !picture.redoAvailable).help("重做").accessibilityLabel("重做")
            }
        }.padding(.horizontal, 20).padding(.vertical, 12).disabled(store.isBusy)
    }
}
