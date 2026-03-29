import XCTest
@testable import AgentVisionShared

final class ActionTests: XCTestCase {

    func testClickActionEncodes() throws {
        let action = ActionRequest.click(at: Point(x: 150, y: 300))
        let data = try JSONEncoder().encode(action)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["action"] as? String, "click")
    }

    func testTypeActionEncodes() throws {
        let action = ActionRequest.type(text: "hello")
        let data = try JSONEncoder().encode(action)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["action"] as? String, "type")
        XCTAssertEqual(json["text"] as? String, "hello")
    }

    func testKeyActionEncodes() throws {
        let action = ActionRequest.key(key: "cmd+a")
        let data = try JSONEncoder().encode(action)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["action"] as? String, "key")
        XCTAssertEqual(json["key"] as? String, "cmd+a")
    }

    func testScrollActionEncodes() throws {
        let action = ActionRequest.scroll(delta: Delta(dx: 0, dy: -100), at: Point(x: 200, y: 300))
        let data = try JSONEncoder().encode(action)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["action"] as? String, "scroll")
    }

    func testDragActionEncodes() throws {
        let action = ActionRequest.drag(from: Point(x: 150, y: 400), to: Point(x: 150, y: 100))
        let data = try JSONEncoder().encode(action)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["action"] as? String, "drag")
    }

    func testActionRoundTrips() throws {
        let action = ActionRequest.click(at: Point(x: 42, y: 99))
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(ActionRequest.self, from: data)
        if case .click(let pt) = decoded {
            XCTAssertEqual(pt.x, 42)
            XCTAssertEqual(pt.y, 99)
        } else {
            XCTFail("Expected click action")
        }
    }

    func testResultEncodes() throws {
        let result = ActionResult(success: true, message: "Clicked at (150, 300)")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.message, "Clicked at (150, 300)")
    }

    func testBoundsCheckPassesForValidCoordinates() {
        let area = CaptureArea(x: 100, y: 200, width: 400, height: 600)
        XCTAssertNil(ActionRequest.click(at: Point(x: 0, y: 0)).boundsError(for: area))
        XCTAssertNil(ActionRequest.click(at: Point(x: 399, y: 599)).boundsError(for: area))
        XCTAssertNil(ActionRequest.click(at: Point(x: 200, y: 300)).boundsError(for: area))
    }

    func testBoundsCheckFailsForOutOfBounds() {
        let area = CaptureArea(x: 100, y: 200, width: 400, height: 600)
        XCTAssertNotNil(ActionRequest.click(at: Point(x: 400, y: 0)).boundsError(for: area))
        XCTAssertNotNil(ActionRequest.click(at: Point(x: 0, y: 600)).boundsError(for: area))
        XCTAssertNotNil(ActionRequest.click(at: Point(x: -1, y: 0)).boundsError(for: area))
        XCTAssertNotNil(ActionRequest.click(at: Point(x: 500, y: 300)).boundsError(for: area))
    }

    func testBoundsCheckDragValidatesBothPoints() {
        let area = CaptureArea(x: 0, y: 0, width: 100, height: 100)
        XCTAssertNotNil(ActionRequest.drag(from: Point(x: 50, y: 50), to: Point(x: 150, y: 50)).boundsError(for: area))
        XCTAssertNotNil(ActionRequest.drag(from: Point(x: -1, y: 50), to: Point(x: 50, y: 50)).boundsError(for: area))
        XCTAssertNil(ActionRequest.drag(from: Point(x: 10, y: 10), to: Point(x: 90, y: 90)).boundsError(for: area))
    }

    func testBoundsCheckScrollAtPosition() {
        let area = CaptureArea(x: 0, y: 0, width: 100, height: 100)
        XCTAssertNil(ActionRequest.scroll(delta: Delta(dx: 0, dy: -50), at: Point(x: 50, y: 50)).boundsError(for: area))
        XCTAssertNotNil(ActionRequest.scroll(delta: Delta(dx: 0, dy: -50), at: Point(x: 150, y: 50)).boundsError(for: area))
    }

    func testBoundsCheckTypeAndKeyAlwaysPass() {
        let area = CaptureArea(x: 0, y: 0, width: 100, height: 100)
        XCTAssertNil(ActionRequest.type(text: "hello").boundsError(for: area))
        XCTAssertNil(ActionRequest.key(key: "enter").boundsError(for: area))
    }

    func testActionFileWriteAndRead() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("action-test-\(UUID().uuidString)")
        let file = dir.appendingPathComponent("action.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let action = ActionRequest.click(at: Point(x: 10, y: 20))
        try ActionFile.write(action, to: file, createDirectory: dir)

        let read = try ActionFile.readAction(from: file)
        if case .click(let pt) = read {
            XCTAssertEqual(pt.x, 10)
        } else {
            XCTFail("Expected click")
        }
    }

    func testResultFileWriteAndRead() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("action-test-\(UUID().uuidString)")
        let file = dir.appendingPathComponent("result.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = ActionResult(success: true, message: "OK")
        try ActionFile.writeResult(result, to: file, createDirectory: dir)

        let read = try ActionFile.readResult(from: file)
        XCTAssertTrue(read.success)
        XCTAssertEqual(read.message, "OK")
    }
}
