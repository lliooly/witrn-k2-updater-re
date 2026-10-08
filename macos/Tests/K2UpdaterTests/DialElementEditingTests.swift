import XCTest
import SwiftUI
import K2Core
@testable import K2Updater

final class DialElementEditingTests: XCTestCase {
    @MainActor func testRowChangesItsOwnElementRatherThanCanvasSelection() {
        let picture = PictureStore()
        let before = picture.project.layout.elements
        picture.selectedElement = 0
        let row = DialElementEditing(picture: picture, elementID: 9)
        row.setFont(6)
        XCTAssertEqual(picture.project.layout.element(9).font, 6)
        XCTAssertEqual(picture.selectedElement, 9)
        for element in before where element.id != 9 {
            XCTAssertEqual(picture.project.layout.element(element.id), element)
        }
        picture.undo()
        XCTAssertEqual(picture.project.layout.elements, before)
        picture.redo()
        XCTAssertEqual(picture.project.layout.element(9).font, 6)
    }

    @MainActor func testCoordinateCommitAfterSelectionChangeKeepsOriginalRowAndUndoGroup() {
        let picture = PictureStore()
        let before = picture.project
        let row = DialElementEditing(picture: picture, elementID: 10)
        let group = UUID()
        row.setCoordinate(77, xAxis: true, group: group)
        picture.selectedElement = 2
        row.setCoordinate(40000, xAxis: true, group: group)
        XCTAssertEqual(picture.project.layout.element(10).x, Int16.max)
        XCTAssertEqual(picture.project.layout.element(2), before.layout.element(2))
        XCTAssertEqual(picture.selectedElement, 2)
        picture.undo()
        XCTAssertEqual(picture.project, before)
        picture.redo()
        XCTAssertEqual(picture.project.layout.element(10).x, Int16.max)
    }

    @MainActor func testVisibilityKeepsPrecisionRulesAndIconFontData() {
        let picture = PictureStore()
        picture.edit {
            var element = $0.layout.element(4); element.enabled = 0; element.font = 255
            $0.layout.update(element); $0.layout.setPrecision(3, value: 0)
            var icon = $0.layout.element(13); icon.enabled = 0; icon.font = 255
            $0.layout.update(icon)
        }
        let before = picture.project.layout
        DialElementEditing(picture: picture, elementID: 4).setVisible(true)
        XCTAssertEqual(picture.project.layout.element(4).font, 1)
        XCTAssertEqual(picture.project.layout.precision(3), 2)
        for index in 0..<8 where index != 3 {
            XCTAssertEqual(picture.project.layout.precision(index), before.precision(index))
        }
        let icon = DialElementEditing(picture: picture, elementID: 13)
        icon.setVisible(true)
        icon.setFont(2)
        XCTAssertEqual(picture.project.layout.element(13).font, 255)
        let valid = picture.project
        DialElementEditing(picture: picture, elementID: 4).setPrecision(7)
        XCTAssertEqual(picture.project, valid)
    }

    @MainActor func testColorOpacityAndPrecisionRemainIndependentPerRow() {
        let picture = PictureStore()
        let before = picture.project.layout
        let row = DialElementEditing(picture: picture, elementID: 15)
        row.setColor(Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 0.5))
        row.setPrecision(7)
        XCTAssertEqual(picture.project.layout.element(15).color, 0x80ff0000)
        XCTAssertEqual(picture.project.layout.precision(7), 7)
        for element in before.elements where element.id != 15 {
            XCTAssertEqual(picture.project.layout.element(element.id), element)
        }
        for index in 0..<7 { XCTAssertEqual(picture.project.layout.precision(index), before.precision(index)) }
        // Reserved bytes outside element records and precision storage are untouched.
        XCTAssertEqual(picture.project.layout.data[174..<224], before.data[174..<224])
        XCTAssertEqual(picture.project.layout.data[232..<400], before.data[232..<400])
    }
}
