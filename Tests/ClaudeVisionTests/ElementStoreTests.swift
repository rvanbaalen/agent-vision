import Foundation
import Testing
@testable import ClaudeVisionShared

@Suite struct ElementStoreTests {

    private func tmpDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("element-store-test-\(UUID().uuidString)")
    }

    private func sampleResult(area: CaptureArea? = nil) -> ElementScanResult {
        let a = area ?? CaptureArea(x: 100, y: 200, width: 800, height: 600)
        return ElementScanResult(area: a, elements: [
            DiscoveredElement(index: 1, source: .accessibility, role: .button, label: "OK",
                              center: Point(x: 50, y: 50), bounds: ElementBounds(x: 30, y: 40, width: 40, height: 20)),
        ])
    }

    @Test func writeAndReadRoundTrips() throws {
        let dir = tmpDir()
        let file = dir.appendingPathComponent("elements.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = sampleResult()
        try ElementStore.write(result, to: file, createDirectory: dir)

        let read = try ElementStore.read(from: file)
        #expect(read != nil)
        #expect(read!.elementCount == 1)
        #expect(read!.elements[0].label == "OK")
    }

    @Test func readReturnsNilWhenNoFile() throws {
        let file = tmpDir().appendingPathComponent("nonexistent.json")
        let read = try ElementStore.read(from: file)
        #expect(read == nil)
    }

    @Test func lookupFindsElementByIndex() throws {
        let result = sampleResult()
        let element = ElementStore.lookup(index: 1, in: result)
        #expect(element != nil)
        #expect(element!.label == "OK")
    }

    @Test func lookupReturnsNilForOutOfRange() throws {
        let result = sampleResult()
        #expect(ElementStore.lookup(index: 0, in: result) == nil)
        #expect(ElementStore.lookup(index: 2, in: result) == nil)
        #expect(ElementStore.lookup(index: 99, in: result) == nil)
    }

    @Test func staleCheckDetectsAreaChange() throws {
        let result = sampleResult(area: CaptureArea(x: 100, y: 200, width: 800, height: 600))
        let currentArea = CaptureArea(x: 150, y: 200, width: 800, height: 600)
        #expect(ElementStore.isStale(result, currentArea: currentArea) == true)
    }

    @Test func staleCheckPassesWhenAreaMatches() throws {
        let area = CaptureArea(x: 100, y: 200, width: 800, height: 600)
        let result = sampleResult(area: area)
        #expect(ElementStore.isStale(result, currentArea: area) == false)
    }
}
