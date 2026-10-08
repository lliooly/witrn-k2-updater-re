import AppKit
import SwiftUI

@main
struct K2UpdaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = UpdaterStore()
    @StateObject private var picture = PictureStore()
    @State private var selection: ToolSection? = .firmware

    var body: some Scene {
        Window("WITRN K2", id: "main") {
            ContentView(store: store, picture: picture, selection: $selection)
                .background(WindowGuard(store: store, picture: picture))
                .onAppear { delegate.store = store; delegate.picture = picture }
        }
        .defaultSize(width: 1100, height: 880)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("打开…") { if selection == .firmware { FirmwarePicker.choose(store) } else { picture.open() } }
                    .keyboardShortcut("o").disabled(store.isBusy)
                Button("保存工程") { picture.save() }.keyboardShortcut("s").disabled(store.isBusy || selection == .firmware)
                Button("工程另存为…") { picture.save(asNew: true) }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(store.isBusy || selection == .firmware)
                Button("刷新设备") { store.refreshDevices() }
                    .keyboardShortcut("r").disabled(store.isBusy)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤销表盘编辑") { picture.undo() }.keyboardShortcut("z").disabled(store.isBusy || selection == .firmware || !picture.undoAvailable)
                Button("重做表盘编辑") { picture.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(store.isBusy || selection == .firmware || !picture.redoAvailable)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: UpdaterStore?
    weak var picture: PictureStore?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let store, store.isBusy { WindowGuard.explainBusy(store); return .terminateCancel }
        return picture?.allowDiscard() == false ? .terminateCancel : .terminateNow
    }
}
