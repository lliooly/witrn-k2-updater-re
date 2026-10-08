import XCTest
@testable import K2Updater
import K2Core

final class EmarkStoreTests: XCTestCase {
    @MainActor func testInvalidDraftPreservesBankAndBlocksSave() async throws {
        let store = EmarkStore(); store.add()
        let before = store.bank, group = UUID()
        let error = store.textEdited("name", text: "中文", group: group) { try $0.setName($1) }
        XCTAssertNotNil(error); XCTAssertEqual(store.bank, before)
        XCTAssertEqual(store.invalidDrafts["name"], "中文")
        XCTAssertEqual(store.invalidFields, ["name"])
        XCTAssertFalse(store.save()); XCTAssertNotNil(store.error)
        XCTAssertNil(store.textEdited("name", text: "Cable", group: group) { try $0.setName($1) })
        XCTAssertEqual(store.record?.name, "Cable"); XCTAssertTrue(store.invalidFields.isEmpty)
        XCTAssertNil(store.invalidDrafts["name"])
    }
    @MainActor func testGroupedTypingUndoRedoAndDraftReset() async throws {
        let store = EmarkStore(); store.add(); let original = store.bank, group = UUID()
        for text in ["A", "AB", "ABC"] {
            XCTAssertNil(store.textEdited("name", text: text, group: group) { try $0.setName($1) })
        }
        _ = store.textEdited("vid", text: "XYZ", group: UUID()) { try $0.setWord(25, EmarkStore.number($1, hexadecimal: true)) }
        let reset = store.inputReset
        store.undo(); XCTAssertEqual(store.bank, original)
        XCTAssertTrue(store.invalidFields.isEmpty); XCTAssertTrue(store.invalidDrafts.isEmpty)
        XCTAssertNotEqual(store.inputReset, reset)
        store.redo(); XCTAssertEqual(store.record?.name, "ABC")
    }
    @MainActor func testIndependentCopiedRecordAndBankRead() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copied = directory.appendingPathComponent("copied.wtemark")
        try EmarkRecord.standard.data.write(to: copied)
        let store = EmarkStore(); store.acceptRead(copied, kind: .emarkCopy)
        XCTAssertEqual(store.bank.count, 0); XCTAssertNotNil(store.copied); XCTAssertFalse(store.dirty)
        var bank = EmarkBank.empty; try bank.append(.standard)
        let file = directory.appendingPathComponent("bank.bin"); try bank.data.write(to: file)
        store.acceptRead(file, kind: .emark)
        XCTAssertEqual(store.bank, bank); XCTAssertTrue(store.dirty); XCTAssertTrue(store.undoAvailable)
        store.undo(); XCTAssertEqual(store.bank.count, 0); XCTAssertNotNil(store.copied)
    }
    @MainActor func testNumericFormatsRejectOverflow() async throws {
        XCTAssertEqual(try EmarkStore.number("0xFFFF", maximum: 65535), 65535)
        XCTAssertEqual(try EmarkStore.number("255", maximum: 255), 255)
        XCTAssertEqual(try EmarkStore.number("ABCD", hexadecimal: true), 0xABCD)
        for text in ["", "-1", "100000000", "XYZ"] { XCTAssertThrowsError(try EmarkStore.number(text, hexadecimal: true)) }
        XCTAssertThrowsError(try EmarkStore.number("256", maximum: 255))
    }
}
