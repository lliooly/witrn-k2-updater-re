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
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(section.rawValue)
                    .font(.title3)
                    .fontWeight(.medium)

                if editor {
                    Text((isEmark ? emark.projectURL?.lastPathComponent : picture.projectURL?.lastPathComponent) ?? "未命名工程")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(dirty ? Color.orange : Color.green)
                            .frame(width: 6, height: 6)
                        Text(dirty ? "未保存" : "已保存")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(section == .monitor ? "实时曲线与采集记录" : "检查固件、备份并更新设备")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 20)

            if editor {
                Menu("文件") {
                    Button("新建工程") {
                        if isEmark { emark.newProject() } else { picture.newProject() }
                    }
                    Button("打开工程") {
                        if isEmark { emark.open() } else { picture.open() }
                    }
                    Button("另存为") {
                        if isEmark { emark.save(asNew: true) } else { picture.save(asNew: true) }
                    }
                    Divider()
                    if isEmark {
                        Button("导入 .wtemark") { emark.importRecords() }
                            .disabled(emark.bank.count >= 10 || !emark.invalidFields.isEmpty)
                        Button("导出配置") { emark.export() }
                            .disabled(emark.record == nil || !emark.invalidFields.isEmpty)
                    } else {
                        Button("导出布局 .pic") { picture.export(.layout) }
                        Button("导出背景 BMP") { picture.export(.background) }
                            .disabled(picture.project.background == nil)
                        Button("导出开机图 BMP") { picture.export(.startup) }
                            .disabled(picture.project.startup == nil)
                    }
                }

                Button("保存") {
                    if isEmark { emark.save() } else { picture.save() }
                }

                Button("↶") {
                    if isEmark { emark.undo() } else { picture.undo() }
                }
                .disabled(isEmark ? !emark.undoAvailable : !picture.undoAvailable)
                .help("撤销")
                .font(.title3)

                Button("↷") {
                    if isEmark { emark.redo() } else { picture.redo() }
                }
                .disabled(isEmark ? !emark.redoAvailable : !picture.redoAvailable)
                .help("重做")
                .font(.title3)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .disabled(store.isBusy)
    }
}
