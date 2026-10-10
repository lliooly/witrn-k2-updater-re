import AppKit
import SwiftUI

@main
struct K2UpdaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = UpdaterStore()
    @StateObject private var picture = PictureStore()
    @StateObject private var emark = EmarkStore()
    @StateObject private var monitor = MonitorStore()
    @State private var selection: ToolSection? = .monitor

    var body: some Scene {
        Window("WITRN K2", id: "main") {
            ContentView(store: store, picture: picture, emark: emark, monitor: monitor, selection: $selection)
                .background(WindowGuard(store: store, picture: picture, emark: emark, monitor: monitor))
                .onAppear { delegate.store = store; delegate.picture = picture; delegate.emark = emark; delegate.monitor = monitor; monitor.attach(store) }
        }
        .defaultSize(width: 1280, height: 880)
        .windowResizability(.contentMinSize)
        // The page title is drawn by the app's own glass top bar, so the window
        // title bar is removed to avoid showing the same title twice.
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("打开…") { if selection == .monitor { monitor.open() } else if selection == .firmware { FirmwarePicker.choose(store) } else if selection == .emark { emark.open() } else { picture.open() } }
                    .keyboardShortcut("o").disabled(store.isBusy)
                Button("保存工程") { if selection == .emark { emark.save() } else { picture.save() } }.keyboardShortcut("s").disabled(store.isBusy || selection == .firmware || selection == .monitor)
                Button("工程另存为…") { if selection == .emark { emark.save(asNew: true) } else { picture.save(asNew: true) } }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(store.isBusy || selection == .firmware || selection == .monitor)
                Button("刷新设备") { store.refreshDevices() }
                    .keyboardShortcut("r").disabled(store.isBusy)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤销编辑") { if selection == .emark { emark.undo() } else { picture.undo() } }.keyboardShortcut("z").disabled(store.isBusy || selection == .firmware || selection == .monitor || (selection == .emark ? !emark.undoAvailable : !picture.undoAvailable))
                Button("重做编辑") { if selection == .emark { emark.redo() } else { picture.redo() } }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(store.isBusy || selection == .firmware || selection == .monitor || (selection == .emark ? !emark.redoAvailable : !picture.redoAvailable))
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: UpdaterStore?
    weak var picture: PictureStore?
    weak var emark: EmarkStore?
    weak var monitor: MonitorStore?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let store, store.isBusy { WindowGuard.explainBusy(store); return .terminateCancel }
        guard picture?.allowDiscard() != false, emark?.allowDiscard() != false else { return .terminateCancel }
        return monitor?.prepareClose({ NSApp.terminate(nil) }) == false ? .terminateCancel : .terminateNow
    }
}
