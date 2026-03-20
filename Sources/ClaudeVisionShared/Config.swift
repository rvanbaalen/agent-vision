import Foundation

public enum Config {
    public static let stateDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude-vision")
    public static let stateFilePath = stateDirectory.appendingPathComponent("state.json")
}
