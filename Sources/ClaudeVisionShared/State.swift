import Foundation

public struct CaptureArea: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct AppState: Codable, Sendable {
    public var pid: Int32
    public var area: CaptureArea?

    public init(pid: Int32, area: CaptureArea?) {
        self.pid = pid
        self.area = area
    }
}

public enum StateFile {
    public static func write(_ state: AppState, to path: URL, createDirectory dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: path)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path.path
        )
    }

    public static func read(from path: URL) throws -> AppState {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(AppState.self, from: data)
    }

    public static func delete(at path: URL) {
        try? FileManager.default.removeItem(at: path)
    }

    public static func isProcessRunning(pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }
}
