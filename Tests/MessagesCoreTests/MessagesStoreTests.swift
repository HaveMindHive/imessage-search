import XCTest
@testable import MessagesCore

final class MessagesStoreTests: XCTestCase {
    func testDecodeAttributedBodyShortForm() {
        // marker + single-byte length prefix (the common case for short message text)
        var bytes = Array("NSString".utf8)
        let text = "Hello from the fold"
        bytes.append(UInt8(text.utf8.count))
        bytes.append(contentsOf: Array(text.utf8))

        XCTAssertEqual(decodeAttributedBody(bytes), text)
    }

    func testDecodeAttributedBodyLongForm() {
        // marker + 0x81 two-byte little-endian length prefix (long message text)
        var bytes = Array("NSString".utf8)
        let text = String(repeating: "a", count: 300)
        bytes.append(0x81)
        bytes.append(UInt8(text.utf8.count & 0xFF))
        bytes.append(UInt8((text.utf8.count >> 8) & 0xFF))
        bytes.append(contentsOf: Array(text.utf8))

        XCTAssertEqual(decodeAttributedBody(bytes), text)
    }

    func testDecodeAttributedBodySkipsAppleInternalKeys() {
        var bytes = Array("NSString".utf8)
        for junk in ["NSDictionary", "__kIMFileTransferGUIDAttributeName"] {
            bytes.append(UInt8(junk.utf8.count))
            bytes.append(contentsOf: Array(junk.utf8))
        }
        let real = "ok"
        bytes.append(UInt8(real.utf8.count))
        bytes.append(contentsOf: Array(real.utf8))

        XCTAssertEqual(decodeAttributedBody(bytes), real)
    }

    func testDecodeAttributedBodyReturnsNilWithoutMarker() {
        XCTAssertNil(decodeAttributedBody(Array("no marker here".utf8)))
        XCTAssertNil(decodeAttributedBody(nil))
        XCTAssertNil(decodeAttributedBody([]))
    }

    func testAppleDateConversionHandlesSecondsAndNanoseconds() {
        // 2021-01-01 00:00:00 UTC in both legacy (seconds) and modern (nanoseconds) encodings
        let seconds: Int64 = 631_152_000
        let nanoseconds = seconds * 1_000_000_000
        XCTAssertEqual(MessagesStore.appleDateToDate(seconds), MessagesStore.appleDateToDate(nanoseconds))
    }
}
