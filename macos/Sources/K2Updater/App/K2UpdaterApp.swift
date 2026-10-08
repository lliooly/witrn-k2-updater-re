import AppKit
import SwiftUI

@main
struct K2UpdaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = UpdaterStore()
    @StateObject private var picture = PictureStore()
    @StateObject private var emark = EmarkStore()
    @State private var selection: ToolSection? = .firmware

    var body: some Scene {
        Window("WITRN K2", id: "main") {
            ContentView(store: store, picture: picture, emark: emark, selection: $selection)
                .background(WindowGuard(store: store, picture: picture, emark: emark))
                .onAppear { delegate.store = store; delegate.picture = picture; delegate.emark = emark }
        }
        .defaultSize(width: 1100, height: 880)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("打开…") { if selection == .firmware { FirmwarePicker.choose(store) } else if selection == .emark { emark.open() } else { picture.open() } }
                    .keyboardShortcut("o").disabled(store.isBusy)
                Button("保存工程") { if selection == .emark { emark.save() } else { picture.save() } }.keyboardShortcut("s").disabled(store.isBusy || selection == .firmware)
                Button("工程另存为…") { if selection == .emark { emark.save(asNew: true) } else { picture.save(asNew: true) } }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(store.isBusy || selection == .firmware)
                Button("刷新设备") { store.refreshDevices() }
                    .keyboardShortcut("r").disabled(store.isBusy)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤销编辑") { if selection == .emark { emark.undo() } else { picture.undo() } }.keyboardShortcut("z").disabled(store.isBusy || selection == .firmware || (selection == .emark ? !emark.undoAvailable : !picture.undoAvailable))
                Button("重做编辑") { if selection == .emark { emark.redo() } else { picture.redo() } }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(store.isBusy || selection == .firmware || (selection == .emark ? !emark.redoAvailable : !picture.redoAvailable))
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: UpdaterStore?
    weak var picture: PictureStore?
    weak var emark: EmarkStore?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let store, store.isBusy { WindowGuard.explainBusy(store); return .terminateCancel }
        return picture?.allowDiscard() == false || emark?.allowDiscard() == false ? .terminateCancel : .terminateNow
    }
}
