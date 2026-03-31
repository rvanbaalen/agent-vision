import Foundation
import Testing
@testable import AgentVisionShared

@Suite struct AgentVisionTests {
    @Test func testConfigPaths() {
        // Verify state directory is under home directory
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(Config.stateDirectory.path.hasPrefix(home.path))
    }

    @Test func testSessionPaths() {
        let sid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
        #expect(Config.sessionDirectory(for: sid).path.contains("sessions/\(sid)"))
        #expect(Config.stateFilePath(for: sid).lastPathComponent == "state.json")
        #expect(Config.elementsFilePath(for: sid).lastPathComponent == "elements.json")
        #expect(Config.actionFilePath(for: sid).lastPathComponent == "action.json")
        #expect(Config.actionResultFilePath(for: sid).lastPathComponent == "action-result.json")
    }

    @Test func testSessionIDValidation() {
        #expect(Config.isValidSessionID("a1b2c3d4-e5f6-7890-abcd-ef1234567890") == true)
        #expect(Config.isValidSessionID("A1B2C3D4-E5F6-7890-ABCD-EF1234567890") == true)
        #expect(Config.isValidSessionID("not-a-uuid") == false)
        #expect(Config.isValidSessionID("") == false)
        #expect(Config.isValidSessionID("../../etc/passwd") == false)
        #expect(Config.isValidSessionID("a1b2c3d4-e5f6-7890-abcd-ef123456789") == false) // too short
        #expect(Config.isValidSessionID("a1b2c3d4-e5f6-7890-abcd-ef12345678901") == false) // too long
    }

    @Test func testGuiPidFilePath() {
        #expect(Config.guiPidFilePath.lastPathComponent == "gui.pid")
        #expect(Config.guiPidFilePath.path.contains(".agent-vision"))
    }
}
