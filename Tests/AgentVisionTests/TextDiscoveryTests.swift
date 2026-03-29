import Foundation
import Testing
@testable import AgentVisionShared

@Suite struct TextDiscoveryTests {

    @Test func visionCoordsConvertToAreaRelative() {
        let areaWidth = 800.0
        let areaHeight = 600.0

        let result = TextDiscovery.convertVisionBounds(
            midX: 0.5, midY: 0.5,
            x: 0.4, y: 0.4, width: 0.2, height: 0.2,
            areaWidth: areaWidth, areaHeight: areaHeight, scaleFactor: 1.0
        )
        #expect(result.center.x == 400.0)
        #expect(result.center.y == 300.0)
        #expect(result.bounds.x == 320.0)
        #expect(result.bounds.width == 160.0)
    }

    @Test func visionCoordsHandleRetinaScaling() {
        let result = TextDiscovery.convertVisionBounds(
            midX: 0.5, midY: 0.5,
            x: 0.4, y: 0.4, width: 0.2, height: 0.2,
            areaWidth: 1600.0, areaHeight: 1200.0, scaleFactor: 2.0
        )
        #expect(result.center.x == 400.0)
        #expect(result.center.y == 300.0)
    }

    @Test func visionCoordsTopLeftOrigin() {
        let result = TextDiscovery.convertVisionBounds(
            midX: 0.1, midY: 0.9,
            x: 0.05, y: 0.85, width: 0.1, height: 0.1,
            areaWidth: 800.0, areaHeight: 600.0, scaleFactor: 1.0
        )
        #expect(result.center.x == 80.0)
        #expect(result.center.y == 60.0)
    }

    @Test func shouldDedup_overlappingWithMatchingLabel() {
        let ocrBounds = ElementBounds(x: 100, y: 100, width: 80, height: 20)
        let axElement = DiscoveredElement(
            index: 1, source: .accessibility, role: .button, label: "Submit",
            center: Point(x: 140, y: 110),
            bounds: ElementBounds(x: 95, y: 95, width: 90, height: 30)
        )
        let result = TextDiscovery.shouldDeduplicate(ocrText: "Submit", ocrBounds: ocrBounds, against: [axElement])
        #expect(result == true)
    }

    @Test func shouldNotDedup_differentLabel() {
        let ocrBounds = ElementBounds(x: 100, y: 100, width: 80, height: 20)
        let axElement = DiscoveredElement(
            index: 1, source: .accessibility, role: .button, label: "Cancel",
            center: Point(x: 140, y: 110),
            bounds: ElementBounds(x: 95, y: 95, width: 90, height: 30)
        )
        let result = TextDiscovery.shouldDeduplicate(ocrText: "Submit", ocrBounds: ocrBounds, against: [axElement])
        #expect(result == false)
    }

    @Test func shouldNotDedup_noOverlap() {
        let ocrBounds = ElementBounds(x: 500, y: 500, width: 80, height: 20)
        let axElement = DiscoveredElement(
            index: 1, source: .accessibility, role: .button, label: "Submit",
            center: Point(x: 140, y: 110),
            bounds: ElementBounds(x: 95, y: 95, width: 90, height: 30)
        )
        let result = TextDiscovery.shouldDeduplicate(ocrText: "Submit", ocrBounds: ocrBounds, against: [axElement])
        #expect(result == false)
    }
}
