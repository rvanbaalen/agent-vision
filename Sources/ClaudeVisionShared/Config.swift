import Foundation

public enum Config {
    public static let stateDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude-vision")
    public static let stateFilePath = stateDirectory.appendingPathComponent("state.json")
    public static let actionFilePath = stateDirectory.appendingPathComponent("action.json")
    public static let actionResultFilePath = stateDirectory.appendingPathComponent("action-result.json")
    public static let elementsFilePath = stateDirectory.appendingPathComponent("elements.json")
}
