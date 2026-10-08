import XCTest
import CoreGraphics
@testable import K2Core

final class PictureTests: XCTestCase {
    func fixture() -> Data {
        var data = PictureLayout.standard.data
        for i in 174..<224 { data[i] = UInt8(truncatingIfNeeded: i * 17) }
        for i in 232..<396 { data[i] = UInt8(truncatingIfNeeded: i * 31) }
        return data
    }
    func testPicRoundTripPreservesAllUnknownBytes() throws {
        let data = fixture()
        let layout = try PictureLayout(data: data)
        XCTAssertEqual(layout.data, data)
        XCTAssertEqual(try JSONDecoder().decode(PictureLayout.self, from: JSONEncoder().encode(layout)), layout)
    }
    func testOneElementChangePreservesOtherRecordsAndReservedBytes() throws {
        let data = fixture(); var layout = try PictureLayout(data: data)
        var element = layout.element(1); element.x = -27; element.y = 300; element.color = 0x80112233
        layout.update(element)
        let decoded = try PictureLayout(data: layout.data).element(1)
        XCTAssertEqual(decoded.x, -27); XCTAssertEqual(decoded.y, 300); XCTAssertEqual(decoded.color, 0x80112233)
        for i in 0..<400 where !(14..<24).contains(i) { XCTAssertEqual(data[i], layout.data[i]) }
        layout.setPrecision(2, value: 5)
        XCTAssertEqual(layout.data[226], 5)
        XCTAssertEqual(layout.data[232..<396], data[232..<396])
    }
    func testMalformedLayoutRejected() {
        XCTAssertThrowsError(try PictureLayout(data: Data(repeating: 0, count: 400)))
        XCTAssertThrowsError(try PictureLayout(data: PictureLayout.standard.data.dropLast()))
        var data = PictureLayout.standard.data; data[12] = 2
        XCTAssertThrowsError(try PictureLayout(data: data))
        data = PictureLayout.standard.data; data[13] = 7
        XCTAssertThrowsError(try PictureLayout(data: data))
        data = PictureLayout.standard.data; data[224] = 10
        XCTAssertThrowsError(try PictureLayout(data: data))
    }
    func testOfficialPrecisionRangesOnlyApplyToEnabledFields() throws {
        for id in [0,1,2,4,5,9,10,15] {
            var layout = PictureLayout.standard
            for element in layout.elements { var next = element; next.enabled = 0; layout.update(next) }
            var element = layout.element(id); element.enabled = 1; layout.update(element)
            let index = try XCTUnwrap(element.precisionIndex)
            for value in [element.precisionRange.lowerBound, element.precisionRange.upperBound] {
                layout.setPrecision(index, value:value); XCTAssertNoThrow(try PictureLayout(data:layout.data))
            }
            layout.setPrecision(index, value:element.precisionRange.upperBound+1)
            XCTAssertThrowsError(try PictureLayout(data:layout.data))
            element.enabled = 0; layout.update(element)
            XCTAssertNoThrow(try PictureLayout(data:layout.data))
        }
    }
    func testRGB565CornersOrderMarkersAndTransparency() throws {
        let n = 240; var pixels = Data(repeating: 0, count: n * n * 4)
        func put(_ x: Int, _ y: Int, _ color: [UInt8]) { pixels.replaceSubrange((y*n+x)*4..<(y*n+x)*4+4, with: color) }
        put(0, 0, [255,0,0,255]); put(n-1,0,[0,255,0,255]); put(0,n-1,[0,0,255,255]); put(n-1,n-1,[255,255,255,0])
        let image = try PixelImage(width:n,height:n,rgba:pixels), data = try image.resourceData(.background)
        XCTAssertEqual(data.count, 115208); XCTAssertEqual(Array(data.prefix(4)), PictureLayout.magic)
        XCTAssertEqual(Array(data[4..<6]), [0,248]); XCTAssertEqual(Array(data[4+(n-1)*2..<6+(n-1)*2]), [224,7])
        XCTAssertEqual(Array(data[4+(n*(n-1))*2..<6+(n*(n-1))*2]), [31,0])
        let result = try PixelImage(resourceData: data, kind:.background)
        XCTAssertEqual(Array(result.rgba.prefix(4)), [255,0,0,255]); XCTAssertEqual(Array(result.rgba.suffix(4)), [0,0,0,255])
        XCTAssertThrowsError(try image.resourceData(.startup))
    }
    func testBMPBottomUpAndRowPadding() throws {
        let image = try PixelImage(width:1,height:2,rgba:Data([255,0,0,255,0,0,255,255]))
        let data = image.bmpData()
        XCTAssertEqual(data.count, 62); XCTAssertEqual(Array(data[54..<58]),[255,0,0,0]); XCTAssertEqual(Array(data[58..<62]),[0,0,255,0])
    }
    func testImageConversionKeepsTopLeftOrientation() throws {
        let image = try PixelImage(width:2,height:2,rgba:Data([255,0,0,255,0,255,0,255,0,0,255,255,255,255,255,255]))
        let converted = try PictureImages.convert(XCTUnwrap(image.cgImage), kind:.background, fit:.stretch)
        XCTAssertEqual(Array(converted.rgba.prefix(4)), [255,0,0,255])
        XCTAssertEqual(Array(converted.rgba[239*4..<240*4]), [0,255,0,255])
        XCTAssertEqual(Array(converted.rgba[(239*240)*4..<(239*240)*4+4]),[0,0,255,255])
        XCTAssertEqual(Array(converted.rgba.suffix(4)),[255,255,255,255])
    }
    func testBMPExportReloadRoundTripOrientation() throws {
        let image = try PixelImage(width:2,height:2,rgba:Data([255,0,0,255,0,255,0,255,0,0,255,255,255,255,255,255]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bmp")
        defer { try? FileManager.default.removeItem(at:url) }
        try image.bmpData().write(to:url)
        let converted = try PictureImages.convert(PictureImages.load(url), kind:.startup, fit:.stretch)
        XCTAssertEqual(Array(converted.rgba.prefix(4)),[255,0,0,255]); XCTAssertEqual(Array(converted.rgba.suffix(4)),[255,255,255,255])
    }
    func testProjectRoundTripAndSchemaChecks() throws {
        var project = PictureProject(); project.layout = try PictureLayout(data:fixture())
        project.startup = try PixelImage(width:235,height:235,rgba:Data(repeating:255,count:235*235*4))
        XCTAssertEqual(try PictureProject.decode(project.encoded()), project)
        project.schema = 2
        XCTAssertThrowsError(try PictureProject.decode(project.encoded()))
        project.schema = 1; project.background = project.startup
        XCTAssertThrowsError(try PictureProject.decode(project.encoded()))
    }
    func testResourceWireRequestUsesBoundPayloadAndWriteCannotCancel() throws {
        var request = BackendRequest(operation:.resourceWrite,dataDirectory:"/tmp")
        request.resourceKind = "layout"; request.resourcePath = "/tmp/layout.pic"; request.resourceSha256 = "hash"; request.confirmed = true
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with:WireCodec.requestData(request)) as? [String:Any])
        XCTAssertEqual(object["resource_kind"] as? String,"layout"); XCTAssertEqual(object["resource_sha256"] as? String,"hash")
        XCTAssertFalse(BackendOperation.resourceWrite.canCancel); XCTAssertFalse(BackendOperation.resourceRestore.canCancel)
        XCTAssertTrue(BackendOperation.resourceRead.canCancel)
    }
}
