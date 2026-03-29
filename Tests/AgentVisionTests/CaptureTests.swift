import XCTest
@testable import AgentVisionShared

final class CaptureTests: XCTestCase {
    func testCaptureAreaToFile() throws {
        let area = CaptureArea(x: 0, y: 0, width: 100, height: 100)
        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-capture-\(UUID().uuidString).png")

        defer { try? FileManager.default.removeItem(at: outputPath) }

        try ScreenCapture.capture(area: area, to: outputPath)

        // Verify the file exists and is a valid PNG
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath.path))
        let data = try Data(contentsOf: outputPath)
        XCTAssertGreaterThan(data.count, 0)
        // PNG magic bytes: 0x89 0x50 0x4E 0x47
        XCTAssertEqual(data[0], 0x89)
        XCTAssertEqual(data[1], 0x50)
        XCTAssertEqual(data[2], 0x4E)
        XCTAssertEqual(data[3], 0x47)
    }

    func testCaptureToDefaultTempPath() throws {
        let area = CaptureArea(x: 0, y: 0, width: 50, height: 50)
        let path = try ScreenCapture.captureToTemp(area: area)

        defer { try? FileManager.default.removeItem(at: URL(fileURLWithPath: path)) }

        XCTAssertTrue(path.hasSuffix(".png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }
}
