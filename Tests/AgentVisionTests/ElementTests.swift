import Foundation
import Testing
@testable import AgentVisionShared

@Suite struct ElementTests {

    @Test func elementEncodesToJSON() throws {
        let element = DiscoveredElement(
            index: 1,
            source: .accessibility,
            role: .button,
            label: "Submit",
            center: Point(x: 245, y: 162),
            bounds: ElementBounds(x: 200, y: 148, width: 90, height: 28)
        )
        let data = try JSONEncoder().encode(element)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["index"] as? Int == 1)
        #expect(json["source"] as? String == "accessibility")
        #expect(json["role"] as? String == "button")
        #expect(json["label"] as? String == "Submit")
    }

    @Test func boundsIntersectionArea() {
        let a = ElementBounds(x: 0, y: 0, width: 100, height: 100)
        let b = ElementBounds(x: 50, y: 50, width: 100, height: 100)
        #expect(a.intersectionArea(with: b) == 2500) // 50x50 overlap

        let c = ElementBounds(x: 200, y: 200, width: 50, height: 50)
        #expect(a.intersectionArea(with: c) == 0) // no overlap
    }

    @Test func boundsArea() {
        let b = ElementBounds(x: 10, y: 20, width: 80, height: 40)
        #expect(b.area == 3200)
    }

    @Test func displayLabelFallsBackForEmptyString() {
        let element = DiscoveredElement(
            index: 1, source: .accessibility, role: .button, label: "",
            center: Point(x: 50, y: 50), bounds: ElementBounds(x: 30, y: 40, width: 40, height: 20)
        )
        #expect(element.displayLabel == "(unlabeled button)")
    }

    @Test func elementRoundTrips() throws {
        let element = DiscoveredElement(
            index: 3,
            source: .ocr,
            role: .staticText,
            label: "Hello World",
            center: Point(x: 100, y: 50),
            bounds: ElementBounds(x: 80, y: 40, width: 40, height: 20)
        )
        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(DiscoveredElement.self, from: data)
        #expect(decoded.index == 3)
        #expect(decoded.source == .ocr)
        #expect(decoded.role == .staticText)
        #expect(decoded.label == "Hello World")
        #expect(decoded.center.x == 100)
        #expect(decoded.center.y == 50)
        #expect(decoded.bounds.width == 40)
    }

    @Test func scanResultEncodesElementCount() throws {
        let elements = [
            DiscoveredElement(index: 1, source: .accessibility, role: .button, label: "OK",
                              center: Point(x: 50, y: 50), bounds: ElementBounds(x: 30, y: 40, width: 40, height: 20)),
            DiscoveredElement(index: 2, source: .ocr, role: .staticText, label: "Cancel",
                              center: Point(x: 150, y: 50), bounds: ElementBounds(x: 130, y: 40, width: 40, height: 20)),
        ]
        let result = ElementScanResult(
            area: CaptureArea(x: 100, y: 200, width: 400, height: 300),
            elements: elements
        )
        let data = try JSONEncoder().encode(result)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["elementCount"] as? Int == 2)
        #expect((json["elements"] as? [[String: Any]])?.count == 2)
    }

    @Test func allRolesEncodeToExpectedStrings() throws {
        let roles: [(ElementRole, String)] = [
            (.button, "button"), (.link, "link"), (.textField, "textField"),
            (.checkbox, "checkbox"), (.menuItem, "menuItem"), (.staticText, "staticText"),
            (.image, "image"), (.group, "group"), (.unknown, "unknown"),
        ]
        for (role, expected) in roles {
            let data = try JSONEncoder().encode(role)
            let str = String(data: data, encoding: .utf8)!
            #expect(str == "\"\(expected)\"")
        }
    }

    @Test func unlabeledElementGetsDefaultLabel() {
        let element = DiscoveredElement(
            index: 1, source: .accessibility, role: .button, label: nil,
            center: Point(x: 50, y: 50), bounds: ElementBounds(x: 30, y: 40, width: 40, height: 20)
        )
        #expect(element.displayLabel == "(unlabeled button)")
    }

    @Test func labeledElementUsesLabel() {
        let element = DiscoveredElement(
            index: 1, source: .accessibility, role: .button, label: "Submit",
            center: Point(x: 50, y: 50), bounds: ElementBounds(x: 30, y: 40, width: 40, height: 20)
        )
        #expect(element.displayLabel == "Submit")
    }
}
