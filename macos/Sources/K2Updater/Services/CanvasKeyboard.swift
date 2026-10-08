import AppKit
import SwiftUI

/// A first responder for the canvas; it leaves hit testing and model state to SwiftUI.
struct CanvasKeyboard: NSViewRepresentable {
    let focusRequest: UUID
    let move: (Int, Int) -> Void
    func makeNSView(context: Context) -> Receiver { Receiver() }
    func updateNSView(_ view: Receiver, context: Context) {
        view.move = move
        if let previous = view.request, previous != focusRequest {
            DispatchQueue.main.async { [weak view] in
                guard let view, let window = view.window else { return }
                window.makeFirstResponder(view)
            }
        }
        view.request = focusRequest
    }
    final class Receiver: NSView {
        var request: UUID?
        var move: ((Int, Int) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func keyDown(with event: NSEvent) {
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { super.keyDown(with: event); return }
            let steps = event.modifierFlags.contains(.shift) ? 10 : 1
            switch event.keyCode {
            case 123: move?(-steps, 0)
            case 124: move?(steps, 0)
            case 125: move?(0, steps)
            case 126: move?(0, -steps)
            default: super.keyDown(with: event)
            }
        }
    }
}
