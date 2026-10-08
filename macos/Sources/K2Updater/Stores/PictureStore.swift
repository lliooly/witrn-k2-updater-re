import AppKit
import Combine
import Foundation
import K2Core
import UniformTypeIdentifiers

@MainActor
final class PictureStore: ObservableObject {
    @Published private(set) var project = PictureProject()
    @Published var selectedElement = 0
    @Published var projectURL: URL?
    @Published var imageImport: ImageImport?
    @Published var error: String?
    @Published private(set) var dirty = false
    @Published private(set) var undoAvailable = false
    @Published private(set) var redoAvailable = false
    private var savedProject = PictureProject()
    private var undoStack: [PictureProject] = []
    private var redoStack: [PictureProject] = []
    private var gestureStart: PictureProject?
    private var lastEditGroup: UUID?
    var element: DialElement { project.layout.element(selectedElement) }

    func edit(coalescing group: UUID? = nil, _ body: (inout PictureProject) throws -> Void) {
        do {
            var next = project; try body(&next)
            guard next != project else { return }
            if gestureStart == nil {
                if group == nil || group != lastEditGroup { undoStack.append(project); trim() }
                redoStack.removeAll()
            }
            lastEditGroup = group
            project = next; changed()
        } catch { self.error = error.localizedDescription }
    }
    func updateElement(_ body: (inout DialElement) -> Void) {
        var element = self.element; body(&element)
        edit {
            $0.layout.update(element)
            if element.enabled == 1, let index = element.precisionIndex,
               !element.precisionRange.contains($0.layout.precision(index)) {
                $0.layout.setPrecision(index, value: element.precisionRange.lowerBound)
            }
        }
    }
    func beginGesture() { if gestureStart == nil { gestureStart = project; lastEditGroup = nil } }
    func endGesture() {
        if let start = gestureStart, start != project { undoStack.append(start); trim(); redoStack.removeAll() }
        gestureStart = nil; changed()
    }
    func undo() { guard let previous = undoStack.popLast() else { return }; lastEditGroup = nil; redoStack.append(project); project = previous; changed() }
    func redo() { guard let next = redoStack.popLast() else { return }; lastEditGroup = nil; undoStack.append(project); project = next; changed() }
    private func trim() { if undoStack.count > 30 { undoStack.removeFirst(undoStack.count - 30) } }
    private func changed() { dirty = project != savedProject; undoAvailable = !undoStack.isEmpty; redoAvailable = !redoStack.isEmpty }

    func newProject() {
        guard allowDiscard() else { return }
        project = PictureProject(); savedProject = project; projectURL = nil
        undoStack.removeAll(); redoStack.removeAll(); changed()
    }
    @discardableResult func allowDiscard() -> Bool {
        guard dirty else { return true }
        let alert = NSAlert(); alert.messageText = "保存表盘工程的更改？"
        alert.informativeText = "工程会保存布局、背景图和开机图。"
        alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "不保存")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertThirdButtonReturn: savedProject = project; changed(); return true
        default: return false
        }
    }
    func open() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "k2project") ?? .data, UTType(filenameExtension: "pic") ?? .data]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }
    func open(_ url: URL) {
        do {
            let limit = url.pathExtension.lowercased() == "pic" ? 400 : 4_194_304
            guard ((try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max) <= limit else {
                throw PictureError.invalid("文件过大")
            }
            let data = try Data(contentsOf: url)
            if url.pathExtension.lowercased() == "pic" {
                let layout = try PictureLayout(data: data); edit { $0.layout = layout }
            } else {
                let next = try PictureProject.decode(data)
                guard allowDiscard() else { return }
                project = next; savedProject = next; projectURL = url; undoStack.removeAll(); redoStack.removeAll(); changed()
            }
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult func save(asNew: Bool = false) -> Bool {
        var target = asNew ? nil : projectURL
        if target == nil {
            let panel = NSSavePanel(); panel.nameFieldStringValue = "我的 K2 表盘.k2project"
            panel.allowedContentTypes = [UTType(filenameExtension: "k2project") ?? .data]
            guard panel.runModal() == .OK else { return false }; target = panel.url
        }
        do { try project.encoded().write(to: target!, options: .atomic); projectURL = target; savedProject = project; changed(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func export(_ kind: PictureResource) {
        do {
            let data = kind == .layout ? project.layout.data : try image(kind).bmpData()
            let panel = NSSavePanel(); panel.nameFieldStringValue = kind == .layout ? "K2 表盘.pic" : "\(kind.title).bmp"
            panel.allowedContentTypes = [UTType(filenameExtension: kind == .layout ? "pic" : "bmp") ?? .data]
            guard panel.runModal() == .OK, let url = panel.url else { return }; try data.write(to: url, options: .atomic)
        } catch { self.error = error.localizedDescription }
    }
    func chooseImage(_ kind: PictureResource) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.bmp, .png, .jpeg]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importImage(url, kind: kind)
    }
    func importImage(_ url: URL, kind: PictureResource) {
        do { imageImport = ImageImport(source: try PictureImages.load(url), kind: kind) }
        catch { self.error = error.localizedDescription }
    }
    func applyImage(_ image: PixelImage, kind: PictureResource) {
        edit { if kind == .startup { $0.startup = image } else { $0.background = image } }; imageImport = nil
    }
    func image(_ kind: PictureResource) throws -> PixelImage {
        guard let image = kind == .startup ? project.startup : project.background else { throw PictureError.invalid("请先选择\(kind.title)") }; return image
    }
    func resourceData(_ kind: PictureResource) throws -> Data { kind == .layout ? project.layout.data : try image(kind).resourceData(kind) }
    func acceptRead(_ url: URL, kind: PictureResource) {
        do {
            let data = try Data(contentsOf: url)
            if kind == .layout { let layout = try PictureLayout(data: data); edit { $0.layout = layout } }
            else { applyImage(try PixelImage(resourceData: data, kind: kind), kind: kind) }
        } catch { self.error = "原始备份已保留，但资源无法加载：\(error.localizedDescription)" }
    }
}
