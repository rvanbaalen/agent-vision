import XCTest
@testable import ClaudeVisionShared

final class StateTests: XCTestCase {
    var testDir: URL!
    var testFile: URL!

    override func setUp() {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-vision-test-\(UUID().uuidString)")
        testFile = testDir.appendingPathComponent("state.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testDir)
    }

    func testAreaEncodesAndDecodes() throws {
        let area = CaptureArea(x: 100, y: 200, width: 800, height: 600)
        let data = try JSONEncoder().encode(area)
        let decoded = try JSONDecoder().decode(CaptureArea.self, from: data)
        XCTAssertEqual(decoded.x, 100)
        XCTAssertEqual(decoded.y, 200)
        XCTAssertEqual(decoded.width, 800)
        XCTAssertEqual(decoded.height, 600)
    }

    func testWriteAndReadState() throws {
        let state = AppState(pid: 12345, area: CaptureArea(x: 10, y: 20, width: 300, height: 200))
        try StateFile.write(state, to: testFile, createDirectory: testDir)
        let read = try XCTUnwrap(StateFile.read(from: testFile))
        XCTAssertEqual(read.pid, 12345)
        XCTAssertEqual(read.area?.width, 300)
    }

    func testWriteStatePidOnly() throws {
        let state = AppState(pid: 99, area: nil)
        try StateFile.write(state, to: testFile, createDirectory: testDir)
        let read = try XCTUnwrap(StateFile.read(from: testFile))
        XCTAssertEqual(read.pid, 99)
        XCTAssertNil(read.area)
    }

    func testReadNonexistentReturnsNil() throws {
        let result = try StateFile.read(from: testFile)
        XCTAssertNil(result)
    }

    func testDeleteRemovesFile() throws {
        let state = AppState(pid: 1, area: nil)
        try StateFile.write(state, to: testFile, createDirectory: testDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path))
        StateFile.delete(at: testFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path))
    }

    func testIsProcessRunningReturnsTrueForSelf() {
        let pid = ProcessInfo.processInfo.processIdentifier
        XCTAssertTrue(StateFile.isProcessRunning(pid: pid))
    }

    func testIsProcessRunningReturnsFalseForBogus() {
        XCTAssertFalse(StateFile.isProcessRunning(pid: 99999))
    }

    func testStateFilePermissions() throws {
        let state = AppState(pid: 1, area: nil)
        try StateFile.write(state, to: testFile, createDirectory: testDir)
        let attributes = try FileManager.default.attributesOfItem(atPath: testFile.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600)
    }
}
