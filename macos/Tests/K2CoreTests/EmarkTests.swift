import XCTest
@testable import K2Core

final class EmarkTests: XCTestCase {
    func testExactRecordOffsetsAndIndependentChecksum() throws {
        var r = EmarkRecord.standard; try r.setName("Cable A")
        try r.setWord(25, 0x11223344); try r.setWord(61, 0x55667788)
        XCTAssertEqual(r.data.count, 66)
        XCTAssertEqual(r.data[20], 2) // Vendor PD 3.x selection stores revision 2.
        try r.setPDVersion(1); XCTAssertEqual(r.data[20], 1)
        XCTAssertThrowsError(try r.setPDVersion(3))
        XCTAssertEqual(Array(r.data.prefix(8)), Array("Cable A\0".utf8))
        XCTAssertEqual(Array(r.data[25..<29]), [0x44, 0x33, 0x22, 0x11])
        XCTAssertEqual(Array(r.data[61..<65]), [0x88, 0x77, 0x66, 0x55])
        XCTAssertEqual(r.data[65], UInt8(truncatingIfNeeded: r.data.prefix(65).reduce(165) { $0 + Int($1) }))
        XCTAssertEqual(try EmarkRecord(data: r.data), r)
        var broken = r.data; broken[61] ^= 1
        XCTAssertThrowsError(try EmarkRecord(data: broken))
    }
    func testEveryFieldChangePreservesUnknownBitsAndOtherBytes() throws {
        for field in EmarkField.identity + EmarkField.cable {
            var r = EmarkRecord.standard
            try r.setWord(field.offset, 0xA597DC42)
            let before = r.data, old = r.word(field.offset), value = field.maximum
            try r.set(field, value: value)
            XCTAssertEqual(r.value(field), value)
            XCTAssertEqual(r.word(field.offset) & ~(field.maximum << field.shift), old & ~(field.maximum << field.shift))
            for i in 0..<65 where !(field.offset..<(field.offset + 4)).contains(i) { XCTAssertEqual(r.data[i], before[i]) }
            XCTAssertNoThrow(try EmarkRecord(data: r.data))
            if field.maximum < .max { XCTAssertThrowsError(try r.set(field, value: field.maximum + 1)) }
        }
    }
    func testLatin1NamesRoundTripWithoutTruncation() throws {
        var r = EmarkRecord.standard
        for name in ["", "é-Cable", String(repeating: "A", count: 18)] {
            try r.setName(name); XCTAssertEqual(r.name, name); XCTAssertEqual(r.data[18], 0)
        }
        let original = r
        for name in ["中文", "A\0B", String(repeating: "A", count: 19)] { XCTAssertThrowsError(try r.setName(name)); XCTAssertEqual(r, original) }
        XCTAssertThrowsError(try r.setPDVersion(4)); XCTAssertThrowsError(try r.setArea(256))
        XCTAssertThrowsError(try r.setWord(20, 1))
    }
    func testTenSlotsAndProjectRoundTripPreserveHeaderAndInactiveData() throws {
        var raw = EmarkBank.empty.data
        raw.replaceSubrange(0..<4, with: [1, 2, 3, 4])
        var bank = try EmarkBank(data: raw)
        for i in 0..<10 { var r = EmarkRecord.standard; try r.setName("Cable \(i)"); try bank.append(r) }
        try bank.select(9)
        XCTAssertEqual(bank.data.count, 666); XCTAssertEqual(bank.data[4], 9); XCTAssertEqual(bank.data[5], 10)
        XCTAssertEqual(Array(bank.data.prefix(4)), [1, 2, 3, 4])
        XCTAssertThrowsError(try bank.append(.standard))
        XCTAssertEqual(try EmarkBank.decode(bank.encoded()), bank)
        try bank.remove(9)
        XCTAssertEqual(bank.selected, 8); XCTAssertEqual(bank.count, 9)
        XCTAssertEqual(bank.data[600..<666], rawRecord("Cable 9"))
        XCTAssertEqual(try EmarkBank.decode(bank.encoded()), bank)
    }
    private func rawRecord(_ name: String) -> Data {
        var r = EmarkRecord.standard; try! r.setName(name); return r.data
    }
    func testMoveAndRemovalFollowSelectedDefault() throws {
        var bank = EmarkBank.empty
        for name in ["A", "B", "C"] { var r = EmarkRecord.standard; try r.setName(name); try bank.append(r) }
        try bank.select(1); try bank.move(1, by: 1)
        XCTAssertEqual(bank.records.map(\.name), ["A", "C", "B"]); XCTAssertEqual(bank.selected, 2)
        try bank.remove(0); XCTAssertEqual(bank.records.map(\.name), ["C", "B"]); XCTAssertEqual(bank.selected, 1)
        try bank.remove(1); try bank.remove(0); XCTAssertEqual(bank.count, 0); XCTAssertEqual(bank.selected, 0)
        XCTAssertThrowsError(try bank.select(0))
    }
    func testBankRejectsInvalidCountSelectedAndActiveChecksum() throws {
        var bank = EmarkBank.empty; try bank.append(.standard)
        for (offset, byte) in [(5, UInt8(11)), (4, UInt8(1)), (71, bank.data[71] ^ 1)] {
            var data = bank.data; data[offset] = byte; XCTAssertThrowsError(try EmarkBank(data: data))
        }
        XCTAssertThrowsError(try EmarkBank(data: bank.data.dropLast()))
        let bad = Data("{\"schema\":2,\"type\":\"k2-emark-project\",\"bank\":\"\"}".utf8)
        XCTAssertThrowsError(try EmarkBank.decode(bad))
        XCTAssertThrowsError(try EmarkBank.decode(Data(repeating: 0, count: 65537)))
    }
}
