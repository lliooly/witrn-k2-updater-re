import AppKit
import SwiftUI
import XCTest
@testable import K2Updater

final class FirmwareSlideDeckTests: XCTestCase {
    @MainActor func testEachPageReservesItsOwnHeightAfterSlidingAndStartingNewTask() {
        func deck(_ step: Int) -> some View {
            FirmwareSlideDeck(step: step, isMoving: .constant(false)) { index in
                Text("Page \(index)").frame(maxWidth: .infinity)
                    .frame(height: CGFloat(100 + index * 50))
            }.frame(width: 600)
        }
        let hosting = NSHostingView(rootView: deck(0))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        for step in [0, 1, 2, 1, 2, 3, 0, 1] {
            hosting.rootView = deck(step)
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            hosting.layoutSubtreeIfNeeded()
            XCTAssertEqual(hosting.fittingSize.height, CGFloat(100 + step * 50), accuracy: 1,
                           "The active page must have a real viewport with its own height at step \(step).")
        }
        withExtendedLifetime(window) {}
    }
}
