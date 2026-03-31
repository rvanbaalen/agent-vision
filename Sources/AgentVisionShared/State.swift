import Foundation

public struct CaptureArea: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    /// The CGWindowID of the tracked window (nil for drag-selected areas).
    public let windowNumber: UInt32?
    /// The name of the application owning the tracked window (e.g. "Terminal", "Safari").
    public let windowOwner: String?
    /// The title of the tracked window (e.g. "~/Sites/agent-vision", "GitHub - Pull Requests").
    public let windowTitle: String?

    public init(x: Double, y: Double, width: Double, height: Double, windowNumber: UInt32? = nil, windowOwner: String? = nil, windowTitle: String? = nil) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.windowNumber = windowNumber
        self.windowOwner = windowOwner
        self.windowTitle = windowTitle
    }

    enum CodingKeys: String, CodingKey {
        case x, y, width, height, windowNumber, windowOwner, windowTitle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        width = try container.decode(Double.self, forKey: .width)
        height = try container.decode(Double.self, forKey: .height)
        windowNumber = try container.decodeIfPresent(UInt32.self, forKey: .windowNumber)
        windowOwner = try container.decodeIfPresent(String.self, forKey: .windowOwner)
        windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
    }
}

public struct AppState: Codable, Sendable {
    public var pid: Int32
    public var area: CaptureArea?
    public var colorIndex: Int

    public init(pid: Int32, area: CaptureArea?, colorIndex: Int = 0) {
        self.pid = pid
        self.area = area
        self.colorIndex = colorIndex
    }

    enum CodingKeys: String, CodingKey {
        case pid, area, colorIndex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pid = try container.decode(Int32.self, forKey: .pid)
        area = try container.decodeIfPresent(CaptureArea.self, forKey: .area)
        colorIndex = try container.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
    }
}

public enum StateFile {
    public static func write(_ state: AppState, to path: URL, createDirectory dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: path, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path.path
        )
    }

    public static func read(from path: URL) throws -> AppState? {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
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
