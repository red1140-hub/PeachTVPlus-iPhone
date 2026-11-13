import XCTest
@testable import PeachTVPlus

final class FlexibleStringTests: XCTestCase {

    private struct Box: Decodable { let v: FlexibleString }

    private func decode(_ json: String) throws -> FlexibleString {
        try JSONDecoder().decode(Box.self, from: Data(json.utf8)).v
    }

    func testDecodesString() throws {
        XCTAssertEqual(try decode(#"{"v":"abc"}"#).value, "abc")
    }

    func testDecodesInt() throws {
        XCTAssertEqual(try decode(#"{"v":123}"#).value, "123")
    }

    func testDecodesIntegerDoubleWithoutTrailingZero() throws {
        XCTAssertEqual(try decode(#"{"v":1700000000.0}"#).value, "1700000000")
    }

    func testDecodesRealDouble() throws {
        XCTAssertEqual(try decode(#"{"v":7.5}"#).value, "7.5")
    }

    func testDecodesBool() throws {
        XCTAssertEqual(try decode(#"{"v":true}"#).value, "1")
        XCTAssertEqual(try decode(#"{"v":false}"#).value, "0")
    }

    func testDecodesNullAsEmpty() throws {
        XCTAssertEqual(try decode(#"{"v":null}"#).value, "")
    }

    func testIntAndEpochHelpers() {
        XCTAssertEqual(FlexibleString("42").intValue, 42)
        XCTAssertNil(FlexibleString("x").intValue)
        XCTAssertEqual(FlexibleString("0").epochDate, Date(timeIntervalSince1970: 0))
        XCTAssertTrue(FlexibleString("").isEmpty)
    }
}
