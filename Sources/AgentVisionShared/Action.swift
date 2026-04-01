import Foundation

public struct Point: Codable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct Delta: Codable, Sendable {
    public let dx: Double
    public let dy: Double
    public init(dx: Double, dy: Double) { self.dx = dx; self.dy = dy }
}

public enum ActionRequest: Codable, Sendable {
    case click(at: Point)
    case type(text: String)
    case key(key: String)
    case scroll(delta: Delta, at: Point)
    case drag(from: Point, to: Point)
    case discoverElements
    case clickElement(index: Int)
    case typeElement(text: String, index: Int)

    enum CodingKeys: String, CodingKey {
        case action, at, text, key, delta, from, to, timestamp, index
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let action = try container.decode(String.self, forKey: .action)
        switch action {
        case "click":
            self = .click(at: try container.decode(Point.self, forKey: .at))
        case "type":
            self = .type(text: try container.decode(String.self, forKey: .text))
        case "key":
            self = .key(key: try container.decode(String.self, forKey: .key))
        case "scroll":
            self = .scroll(
                delta: try container.decode(Delta.self, forKey: .delta),
                at: try container.decode(Point.self, forKey: .at)
            )
        case "drag":
            self = .drag(
                from: try container.decode(Point.self, forKey: .from),
                to: try container.decode(Point.self, forKey: .to)
            )
        case "discoverElements":
            self = .discoverElements
        case "clickElement":
            self = .clickElement(index: try container.decode(Int.self, forKey: .index))
        case "typeElement":
            self = .typeElement(
                text: try container.decode(String.self, forKey: .text),
                index: try container.decode(Int.self, forKey: .index)
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .action, in: container, debugDescription: "Unknown action: \(action)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let timestamp = Int(Date().timeIntervalSince1970)
        try container.encode(timestamp, forKey: .timestamp)
        switch self {
        case .click(let pt):
            try container.encode("click", forKey: .action)
            try container.encode(pt, forKey: .at)
        case .type(let text):
            try container.encode("type", forKey: .action)
            try container.encode(text, forKey: .text)
        case .key(let key):
            try container.encode("key", forKey: .action)
            try container.encode(key, forKey: .key)
        case .scroll(let delta, let pt):
            try container.encode("scroll", forKey: .action)
            try container.encode(delta, forKey: .delta)
            try container.encode(pt, forKey: .at)
        case .drag(let from, let to):
            try container.encode("drag", forKey: .action)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
        case .discoverElements:
            try container.encode("discoverElements", forKey: .action)
        case .clickElement(let index):
            try container.encode("clickElement", forKey: .action)
            try container.encode(index, forKey: .index)
        case .typeElement(let text, let index):
            try container.encode("typeElement", forKey: .action)
            try container.encode(text, forKey: .text)
            try container.encode(index, forKey: .index)
        }
    }

    public var isDiscoverElements: Bool {
        if case .discoverElements = self { return true }
        return false
    }

    public var isElementBased: Bool {
        switch self {
        case .clickElement, .typeElement, .discoverElements: return true
        default: return false
        }
    }

    public func boundsError(for area: CaptureArea) -> String? {
        func check(_ point: Point, label: String) -> String? {
            if point.x < 0 || point.x >= area.width || point.y < 0 || point.y >= area.height {
                return "Error: \(label)coordinates (\(Int(point.x)), \(Int(point.y))) are outside the selected area (\(Int(area.width))x\(Int(area.height)))"
            }
            return nil
        }
        switch self {
        case .click(let pt): return check(pt, label: "")
        case .scroll(_, let pt): return check(pt, label: "")
        case .drag(let from, let to): return check(from, label: "'from' ") ?? check(to, label: "'to' ")
        case .type, .key, .discoverElements, .clickElement, .typeElement: return nil
        }
    }

    public func toAbsolute(area: CaptureArea) -> ActionRequest {
        func abs(_ pt: Point) -> Point { Point(x: area.x + pt.x, y: area.y + pt.y) }
        switch self {
        case .click(let pt): return .click(at: abs(pt))
        case .scroll(let delta, let pt): return .scroll(delta: delta, at: abs(pt))
        case .drag(let from, let to): return .drag(from: abs(from), to: abs(to))
        case .type, .key, .discoverElements, .clickElement, .typeElement: return self
        }
    }
}

public struct ActionResult: Codable, Sendable {
    public let success: Bool
    public let message: String
    public init(success: Bool, message: String) { self.success = success; self.message = message }
}

public enum ActionFile {
    public static func write(_ action: ActionRequest, to path: URL, createDirectory dir: URL, focusTimeout: Int? = nil) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let timeout = focusTimeout {
            let encoded = try JSONEncoder().encode(action)
            var dict = (try JSONSerialization.jsonObject(with: encoded) as? [String: Any]) ?? [:]
            dict["focusTimeout"] = timeout
            let data = try JSONSerialization.data(withJSONObject: dict)
            try data.write(to: path, options: .atomic)
        } else {
            let data = try JSONEncoder().encode(action)
            try data.write(to: path, options: .atomic)
        }
    }
    public static func readAction(from path: URL) throws -> ActionRequest {
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(ActionRequest.self, from: data)
    }
    public static func writeResult(_ result: ActionResult, to path: URL, createDirectory dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(result)
        try data.write(to: path, options: .atomic)
    }
    public static func readResult(from path: URL) throws -> ActionResult {
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(ActionResult.self, from: data)
    }
    public static func delete(at path: URL) {
        try? FileManager.default.removeItem(at: path)
    }
}
