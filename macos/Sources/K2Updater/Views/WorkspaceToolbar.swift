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
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label(section.rawValue, systemImage: section.symbol).font(.title3.weight(.semibold))
                if editor {
                    Text((isEmark ? emark.projectURL?.lastPathComponent : picture.projectURL?.lastPathComponent) ?? "未命名工程")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: dirty ? "circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(dirty ? .orange : .green).font(.caption)
                        Text(dirty ? "未保存更改" : "已保存").font(.callout).foregroundStyle(dirty ? .orange : .secondary)
                    }
                } else {
                    Text(section == .monitor ? "实时曲线与采集记录" : "检查固件、备份并更新设备")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            if editor {
                Menu {
                    Button { if isEmark { emark.newProject() } else { picture.newProject() } } label: {
                        Label("新建工程", systemImage: "doc.badge.plus")
                    }
                    Button { if isEmark { emark.open() } else { picture.open() } } label: {
                        Label("打开工程", systemImage: "folder")
                    }
                    Button { if isEmark { emark.save(asNew: true) } else { picture.save(asNew: true) } } label: {
                        Label("工程另存为", systemImage: "doc.badge.arrow.up")
                    }
                    Divider()
                    if isEmark {
                        Button { emark.importRecords() } label: {
                            Label("导入 .wtemark", systemImage: "square.and.arrow.down")
                        }.disabled(emark.bank.count >= 10 || !emark.invalidFields.isEmpty)
                        Button { emark.export() } label: {
                            Label("导出选中配置", systemImage: "square.and.arrow.up")
                        }.disabled(emark.record == nil || !emark.invalidFields.isEmpty)
                    } else {
                        Button { picture.export(.layout) } label: {
                            Label("导出布局 .pic", systemImage: "square.and.arrow.up")
                        }
                        Button { picture.export(.background) } label: {
                            Label("导出背景 BMP", systemImage: "photo")
                        }.disabled(picture.project.background == nil)
                        Button { picture.export(.startup) } label: {
                            Label("导出开机图 BMP", systemImage: "photo")
                        }.disabled(picture.project.startup == nil)
                    }
                } label: {
                    Label("文件", systemImage: "folder")
                }
                Button { if isEmark { emark.save() } else { picture.save() } } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                }
                Button { if isEmark { emark.undo() } else { picture.undo() } } label: {
                    Image(systemName: "arrow.uturn.backward")
                }.disabled(isEmark ? !emark.undoAvailable : !picture.undoAvailable).help("撤销")
                Button { if isEmark { emark.redo() } else { picture.redo() } } label: {
                    Image(systemName: "arrow.uturn.forward")
                }.disabled(isEmark ? !emark.redoAvailable : !picture.redoAvailable).help("重做")
            }
        }.padding(.horizontal, 20).padding(.vertical, 14).disabled(store.isBusy)
    }
}
