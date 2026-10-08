import AppKit
import Combine
import Foundation
import K2Core
import UniformTypeIdentifiers

@MainActor
final class EmarkStore: ObservableObject {
    @Published private(set) var bank = EmarkBank.empty
    @Published var selected = 0
    @Published var projectURL: URL?
    @Published var copied: EmarkRecord?
    @Published var error: String?
    @Published private(set) var dirty = false
    @Published private(set) var undoAvailable = false
    @Published private(set) var redoAvailable = false
    @Published private(set) var invalidFields: Set<String> = []
    @Published private(set) var inputReset = UUID()
    private(set) var invalidDrafts: [String: String] = [:]
    private(set) var validationMessages: [String: String] = [:]
    private var saved = EmarkBank.empty
    private var undoStack: [EmarkBank] = []
    private var redoStack: [EmarkBank] = []
    private var lastGroup: UUID?
    var record: EmarkRecord? { (0..<bank.count).contains(selected) ? bank.record(selected) : nil }

    func edit(group: UUID? = nil, _ body: (inout EmarkBank) throws -> Void) {
        do {
            var next = bank; try body(&next); guard next != bank else { return }
            if group == nil || group != lastGroup {
                undoStack.append(bank); if undoStack.count > 30 { undoStack.removeFirst() }
            }
            redoStack.removeAll(); lastGroup = group; bank = next; changed()
        } catch { self.error = error.localizedDescription }
    }
    private func changed() {
        selected = bank.count == 0 ? 0 : min(max(0, selected), bank.count - 1)
        dirty = bank != saved; undoAvailable = !undoStack.isEmpty; redoAvailable = !redoStack.isEmpty
    }
    func undo() { guard let next = undoStack.popLast() else { return }; redoStack.append(bank); bank = next; lastGroup = nil; clearDraftErrors(); changed() }
    func redo() { guard let next = redoStack.popLast() else { return }; undoStack.append(bank); bank = next; lastGroup = nil; clearDraftErrors(); changed() }
    func add(_ record: EmarkRecord = .standard) { let index = bank.count; edit { try $0.append(record) }; if bank.count > index { selected = index } }
    func duplicate() { if let record { add(record) } }
    func remove() { let index = selected; edit { try $0.remove(index) }; clearDraftErrors() }
    func move(_ delta: Int) { let index = selected; edit { try $0.move(index, by: delta) }; selected = max(0, min(bank.count - 1, index + delta)) }
    func setDefault() { let index = selected; edit { try $0.select(index) } }
    func update(group: UUID? = nil, _ body: (inout EmarkRecord) throws -> Void) {
        guard var r = record else { return }
        do { try body(&r); let index = selected; edit(group: group) { try $0.update(index, record: r) } }
        catch { self.error = error.localizedDescription }
    }
    func textEdited(_ key: String, text: String, group: UUID, change: (inout EmarkRecord, String) throws -> Void) -> String? {
        guard var r = record else { return nil }
        do {
            try change(&r, text); invalidFields.remove(key); invalidDrafts.removeValue(forKey: key); validationMessages.removeValue(forKey: key)
            let index = selected; edit(group: group) { try $0.update(index, record: r) }; return nil
        } catch { invalidFields.insert(key); invalidDrafts[key] = text; validationMessages[key] = error.localizedDescription; return error.localizedDescription }
    }
    func clearDraftErrors() { invalidFields.removeAll(); invalidDrafts.removeAll(); validationMessages.removeAll(); inputReset = UUID() }
    static func number(_ text: String, maximum: UInt32 = .max, hexadecimal: Bool = false) throws -> UInt32 {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasPrefix = value.lowercased().hasPrefix("0x")
        guard let number = UInt32(hasPrefix ? String(value.dropFirst(2)) : value, radix: (hasPrefix || hexadecimal) ? 16 : 10), number <= maximum else {
            throw PictureError.invalid("输入超出范围或格式无效")
        }; return number
    }
    func newProject() {
        guard allowDiscard() else { return }
        bank = .empty; saved = bank; projectURL = nil; selected = 0
        undoStack.removeAll(); redoStack.removeAll(); clearDraftErrors(); changed()
    }
    @discardableResult func allowDiscard() -> Bool {
        guard dirty || !invalidFields.isEmpty else { return true }
        let alert = NSAlert(); alert.messageText = "保存 E-Mark 配置的更改？"
        alert.informativeText = invalidFields.isEmpty ? "保存完整配置集合及默认组。" : "存在未完成或无效的输入，请修改后保存，或选择不保存。"
        alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "不保存")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertThirdButtonReturn: saved = bank; clearDraftErrors(); changed(); return true
        default: return false
        }
    }
    func open() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "k2emark") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }; open(url)
    }
    func open(_ url: URL) {
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max <= 65536 else { throw PictureError.invalid("工程文件过大") }
            let next = try EmarkBank.decode(Data(contentsOf: url)); guard allowDiscard() else { return }
            bank = next; saved = next; projectURL = url; selected = next.selected
            undoStack.removeAll(); redoStack.removeAll(); clearDraftErrors(); changed()
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult func save(asNew: Bool = false) -> Bool {
        guard invalidFields.isEmpty else { error = "请先修正编辑器中的无效输入"; return false }
        var target = asNew ? nil : projectURL
        if target == nil {
            let panel = NSSavePanel(); panel.nameFieldStringValue = "我的 K2 E-Mark.k2emark"
            panel.allowedContentTypes = [UTType(filenameExtension: "k2emark") ?? .data]
            guard panel.runModal() == .OK else { return false }; target = panel.url
        }
        do { try bank.encoded().write(to: target!, options: .atomic); projectURL = target; saved = bank; changed(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func importRecords() {
        guard invalidFields.isEmpty else { error = "请先修正编辑器中的无效输入"; return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "wtemark") ?? .data]; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        do {
            guard panel.urls.count <= EmarkBank.capacity - bank.count else { throw PictureError.invalid("导入后超过 10 组配置") }
            let records = try panel.urls.map { url -> EmarkRecord in
                guard (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize == EmarkRecord.size else { throw PictureError.invalid("\(url.lastPathComponent)不是 66 字节配置") }
                return try EmarkRecord(data: Data(contentsOf: url))
            }
            let index = bank.count; edit { for r in records { try $0.append(r) } }; selected = index
        } catch { self.error = error.localizedDescription }
    }
    func export(_ r: EmarkRecord? = nil) {
        guard invalidFields.isEmpty else { error = "请先修正编辑器中的无效输入"; return }
        guard let value = r ?? record else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "K2-\(value.name.replacingOccurrences(of: "/", with: "-")).wtemark"
        panel.allowedContentTypes = [UTType(filenameExtension: "wtemark") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try value.data.write(to: url, options: .atomic) } catch { self.error = error.localizedDescription }
    }
    func acceptRead(_ url: URL, kind: PictureResource) {
        do {
            let data = try Data(contentsOf: url)
            if kind == .emarkCopy { copied = try EmarkRecord(data: data) }
            else { let next = try EmarkBank(data: data); edit { $0 = next }; selected = next.selected; clearDraftErrors() }
        } catch { self.error = "原始备份已保存，但配置无法加载：\(error.localizedDescription)" }
    }
}
