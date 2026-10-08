import SwiftUI
import K2Core

struct EmarkView: View {
    @ObservedObject var emark: EmarkStore
    @ObservedObject var store: UpdaterStore
    @State private var writeIntent: ResourceWriteIntent?
    @State private var confirmDelete = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("虚拟 E-Mark").font(.title2).fontWeight(.semibold)
                Spacer()
                Text((emark.dirty || !emark.invalidFields.isEmpty) ? "未保存" : "已保存").font(.caption).foregroundStyle(.secondary)
            }
            Text("编辑 K2 模拟的数据线身份。配置在 DFU 模式下读写；使用时在 K2 菜单选择虚拟 E-Mark。参数不会改变实际线材的电气能力。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("打开工程…") { emark.open() }
                Button("保存工程") { emark.save() }
                Text(emark.projectURL?.lastPathComponent ?? "未命名配置集合").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("导入 .wtemark…") { emark.importRecords() }.disabled(emark.bank.count >= 10 || !emark.invalidFields.isEmpty)
                Button("导出选中配置…") { emark.export() }.disabled(emark.record == nil || !emark.invalidFields.isEmpty)
            }
            HStack {
                Button("读取设备配置") {
                    guard emark.allowDiscard() else { return }
                    store.readResource(.emark) { url, kind in emark.acceptRead(url, kind: kind) }
                }.disabled(!store.canUseResources)
                Button("读取复制数据") { store.readResource(.emarkCopy) { url, kind in emark.acceptRead(url, kind: kind) } }.disabled(!store.canUseResources)
                Spacer()
                Button("备份并写入配置") {
                    writeIntent = ResourceWriteIntent(kind: .emark, data: emark.bank.data, manifest: nil, manifestHash: nil)
                }.buttonStyle(.borderedProminent).disabled(!store.canUseResources || !emark.invalidFields.isEmpty)
            }
            HStack(alignment: .top, spacing: 16) {
                configurationList.frame(width: 205)
                EmarkEditor(emark: emark).frame(maxWidth: .infinity, alignment: .topLeading).id(emark.selected)
            }.padding(14).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            if let copied = emark.copied {
                HStack {
                    Label("复制数据：\(copied.name.isEmpty ? "未命名" : copied.name)", systemImage: "doc.on.doc")
                    Spacer()
                    Button("添加到配置集合") { emark.add(copied) }.disabled(emark.bank.count >= 10 || !emark.invalidFields.isEmpty)
                    Button("导出…") { emark.export(copied) }
                }.font(.callout)
            }
        }.disabled(store.isBusy)
        .alert("写入 \(emark.bank.count) 组 E-Mark 配置？", isPresented: Binding(get: { writeIntent != nil }, set: { if !$0 { writeIntent = nil } })) {
            Button("取消", role: .cancel) { writeIntent = nil }
            Button("备份并写入") { if let intent = writeIntent { store.writeResource(intent) }; writeIntent = nil }
        } message: {
            Text("\(emark.bank.count == 0 ? "将清空有效配置列表。" : "默认组：第 \(emark.bank.selected + 1) 组。")先双遍备份配置扇区，再写入并完整读回校验。复制数据、表盘和开机图保留。请保持连接。")
        }
        .alert("删除这组配置？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { emark.remove() }
        } message: { Text("只修改本地配置集合，写入后才改变设备。") }
        .alert("E-Mark 操作未完成", isPresented: Binding(get: { emark.error != nil }, set: { if !$0 { emark.error = nil } })) {
            Button("好") { emark.error = nil }
        } message: { Text(emark.error ?? "") }
    }
    private var configurationList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("配置 \(emark.bank.count) / 10").font(.headline)
            List(0..<emark.bank.count, id: \.self, selection: $emark.selected) { index in
                HStack {
                    Text("\(index + 1). \(emark.bank.record(index).name.isEmpty ? "未命名" : emark.bank.record(index).name)").lineLimit(1)
                    if index == emark.bank.selected { Image(systemName: "star.fill").foregroundStyle(.secondary).font(.caption) }
                }.tag(index)
            }.frame(height: 280).disabled(!emark.invalidFields.isEmpty)
            HStack {
                Button { emark.add() } label: { Image(systemName: "plus") }.help("新增配置").disabled(emark.bank.count >= 10 || !emark.invalidFields.isEmpty)
                Button { confirmDelete = true } label: { Image(systemName: "minus") }.help("删除配置").disabled(emark.record == nil || !emark.invalidFields.isEmpty)
                Button { emark.duplicate() } label: { Image(systemName: "doc.on.doc") }.help("复制配置").disabled(emark.record == nil || emark.bank.count >= 10 || !emark.invalidFields.isEmpty)
                Spacer()
            }
            HStack {
                Button { emark.move(-1) } label: { Image(systemName: "arrow.up") }.disabled(emark.selected <= 0)
                Button { emark.move(1) } label: { Image(systemName: "arrow.down") }.disabled(emark.selected >= emark.bank.count - 1)
                Button("设为默认") { emark.setDefault() }.disabled(emark.record == nil || emark.selected == emark.bank.selected)
            }.disabled(!emark.invalidFields.isEmpty)
        }
    }
}

struct EmarkEditor: View {
    @ObservedObject var emark: EmarkStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let r = emark.record {
                EmarkInput(title: "名称", value: r.name, key: "name", emark: emark) { record, text in try record.setName(text) }
                Picker("PD 版本", selection: Binding(get: { r.pdVersion }, set: { value in emark.update { try $0.setPDVersion(value) } })) {
                    Text("PD 2.0").tag(1); Text("PD 3.x").tag(2)
                }
                GroupBox("身份信息") { fields(EmarkField.identity, record: r) }
                GroupBox("线材能力") { fields(EmarkField.cable, record: r) }
                DisclosureGroup("原始 VDO 与扩展数据") {
                    VStack(spacing: 8) {
                        EmarkInput(title: "配置区域（0…255）", value: String(r.area), key: "area", emark: emark) { record, text in
                            try record.setArea(Int(EmarkStore.number(text, maximum: 255)))
                        }
                        ForEach(0..<11, id: \.self) { index in
                            EmarkInput(title: EmarkField.rawTitles[index], value: String(format: "%08X", r.word(21 + index * 4)), key: "raw\(index)", emark: emark) { record, text in
                                try record.setWord(21 + index * 4, EmarkStore.number(text, hexadecimal: true))
                            }
                        }
                        Text("十六进制，最多 8 位。字段修改保留未知位；单条校验自动更新。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 8)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("尚无配置").font(.headline)
                    Text("读取设备、导入 .wtemark，或点 + 新增。新配置由本应用生成，需要按线材身份调整参数。")
                        .foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            }
        }
    }
    private func fields(_ fields: [EmarkField], record: EmarkRecord) -> some View {
        VStack(spacing: 8) {
            ForEach(fields) { field in
                if !field.options.isEmpty {
                    Picker(field.title, selection: Binding(get: { record.value(field) }, set: { value in emark.update { try $0.set(field, value: value) } })) {
                        ForEach(Array(field.options.enumerated()), id: \.offset) { item in Text(item.element).tag(UInt32(item.offset)) }
                    }
                } else {
                    EmarkInput(title: field.title, value: String(format: field.width > 16 ? "%08X" : "%04X", record.value(field)), key: field.id, emark: emark) { record, text in
                        try record.set(field, value: EmarkStore.number(text, maximum: field.maximum, hexadecimal: true))
                    }
                }
            }
        }.padding(6)
    }
}

struct EmarkInput: View {
    let title: String
    let value: String
    let key: String
    @ObservedObject var emark: EmarkStore
    let change: (inout EmarkRecord, String) throws -> Void
    @State private var text = ""
    @State private var problem: String?
    @State private var group = UUID()
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).frame(width: 140, alignment: .leading)
                TextField(title, text: $text).labelsHidden().textFieldStyle(.roundedBorder).focused($focused)
                    .accessibilityLabel(title)
            }
            if let problem { Text(problem).font(.caption).foregroundStyle(.red) }
        }
        .onAppear { text = emark.invalidDrafts[key] ?? value; problem = emark.validationMessages[key] }
        .onChange(of: focused) { active in if active { group = UUID() } else if problem == nil { text = value } }
        .onChange(of: text) { next in
            guard focused else { return }
            problem = emark.textEdited(key, text: next, group: group, change: change)
        }
        .onChange(of: value) { next in if !focused { text = next } }
        .onChange(of: emark.inputReset) { _ in focused = false; problem = nil; text = value }
    }
}
