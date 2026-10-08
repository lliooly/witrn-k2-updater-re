import AppKit
import UniformTypeIdentifiers

@MainActor
enum FirmwarePicker {
    static func choose(_ store: UpdaterStore) {
        let panel = NSOpenPanel()
        panel.title = "选择 K2 固件"
        panel.prompt = "检查固件"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "k2") ?? .data]
        if panel.runModal() == .OK, let url = panel.url { store.inspect(url) }
    }
}
