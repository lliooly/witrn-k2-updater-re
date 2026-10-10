import AppKit
import SwiftUI

struct WindowGuard: NSViewRepresentable {
    let store: UpdaterStore
    let picture: PictureStore
    let emark: EmarkStore
    let monitor: MonitorStore
    func makeCoordinator() -> Coordinator { Coordinator(store, picture, emark, monitor) }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window, window.delegate !== context.coordinator else { return }
            context.coordinator.originalDelegate = window.delegate
            window.delegate = context.coordinator
            WindowGuard.hideStockToolbar(window)
        }
    }

    /// Hides the stock window toolbar.
    ///
    /// SwiftUI fills it with the system sidebar toggle, whose own strip stays
    /// empty once the navigation sidebar carries its own control. The app adds
    /// no toolbar items of its own, so the toolbar is hidden outright.
    @MainActor
    static func hideStockToolbar(_ window: NSWindow) {
        window.toolbar?.isVisible = false
    }

    @MainActor
    static func explainBusy(_ store: UpdaterStore) {
        let alert = NSAlert()
        alert.messageText = "任务尚未完成"
        alert.informativeText = store.operation?.isWrite == true
            ? "备份并写入正在进行，请等待任务完成再关闭应用。"
            : "只读操作正在进行。可以继续等待，或在主窗口取消操作。"
        alert.addButton(withTitle: "继续等待")
        alert.runModal()
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        let store: UpdaterStore
        let picture: PictureStore
        let emark: EmarkStore
        let monitor: MonitorStore
        weak var originalDelegate: NSWindowDelegate?
        init(_ store: UpdaterStore, _ picture: PictureStore, _ emark: EmarkStore, _ monitor: MonitorStore) { self.store = store; self.picture = picture; self.emark = emark; self.monitor = monitor }
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || originalDelegate?.responds(to: selector) == true
        }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            if originalDelegate?.responds(to: selector) == true { return originalDelegate }
            return super.forwardingTarget(for: selector)
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if store.isBusy { WindowGuard.explainBusy(store); return false }
            guard picture.allowDiscard(), emark.allowDiscard() else { return false }
            guard monitor.prepareClose({ [weak sender] in sender?.performClose(nil) }) else { return false }
            return originalDelegate?.windowShouldClose?(sender) ?? true
        }
    }
}
