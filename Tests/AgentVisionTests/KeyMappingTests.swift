import XCTest
@testable import AgentVisionShared

final class KeyMappingTests: XCTestCase {
    func testParseSimpleKey() throws {
        let parsed = try KeyMapping.parse("enter")
        XCTAssertEqual(parsed.keyCode, 0x24)
        XCTAssertTrue(parsed.modifiers.isEmpty)
    }
    func testParseTab() throws {
        let parsed = try KeyMapping.parse("tab")
        XCTAssertEqual(parsed.keyCode, 0x30)
    }
    func testParseEscape() throws {
        let parsed = try KeyMapping.parse("escape")
        XCTAssertEqual(parsed.keyCode, 0x35)
    }
    func testParseArrowKeys() throws {
        XCTAssertEqual(try KeyMapping.parse("up").keyCode, 0x7E)
        XCTAssertEqual(try KeyMapping.parse("down").keyCode, 0x7D)
        XCTAssertEqual(try KeyMapping.parse("left").keyCode, 0x7B)
        XCTAssertEqual(try KeyMapping.parse("right").keyCode, 0x7C)
    }
    func testParseSingleChar() throws {
        let parsed = try KeyMapping.parse("a")
        XCTAssertEqual(parsed.keyCode, 0x00)
        XCTAssertTrue(parsed.modifiers.isEmpty)
    }
    func testParseWithModifiers() throws {
        let parsed = try KeyMapping.parse("cmd+a")
        XCTAssertEqual(parsed.keyCode, 0x00)
        XCTAssertTrue(parsed.modifiers.contains(.maskCommand))
    }
    func testParseMultipleModifiers() throws {
        let parsed = try KeyMapping.parse("cmd+shift+z")
        XCTAssertEqual(parsed.keyCode, 0x06)
        XCTAssertTrue(parsed.modifiers.contains(.maskCommand))
        XCTAssertTrue(parsed.modifiers.contains(.maskShift))
    }
    func testParseAltModifier() throws {
        let parsed = try KeyMapping.parse("alt+tab")
        XCTAssertEqual(parsed.keyCode, 0x30)
        XCTAssertTrue(parsed.modifiers.contains(.maskAlternate))
    }
    func testParseCtrlModifier() throws {
        let parsed = try KeyMapping.parse("ctrl+c")
        XCTAssertEqual(parsed.keyCode, 0x08)
        XCTAssertTrue(parsed.modifiers.contains(.maskControl))
    }
    func testParseUnknownKeyThrows() {
        XCTAssertThrowsError(try KeyMapping.parse("nonexistent"))
    }
    func testParseSpaceKey() throws {
        let parsed = try KeyMapping.parse("space")
        XCTAssertEqual(parsed.keyCode, 0x31)
    }
    func testParseDeleteAndBackspace() throws {
        XCTAssertEqual(try KeyMapping.parse("delete").keyCode, 0x75)
        XCTAssertEqual(try KeyMapping.parse("backspace").keyCode, 0x33)
    }
}
