import Testing
@testable import ClaudeVisionShared

@Suite struct ClaudeVisionTests {
    @Test func testConfigPaths() {
        // Verify state directory is under home directory
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(Config.stateDirectory.path.hasPrefix(home.path))
        #expect(Config.stateFilePath.lastPathComponent == "state.json")
    }
}
