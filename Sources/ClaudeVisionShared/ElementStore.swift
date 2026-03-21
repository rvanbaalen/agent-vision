import Foundation

public enum ElementStore {
    public static func write(_ result: ElementScanResult, to path: URL, createDirectory dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(result)
        try data.write(to: path, options: .atomic)
    }

    public static func read(from path: URL) throws -> ElementScanResult? {
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(ElementScanResult.self, from: data)
    }

    public static func lookup(index: Int, in result: ElementScanResult) -> DiscoveredElement? {
        result.elements.first { $0.index == index }
    }

    public static func isStale(_ result: ElementScanResult, currentArea: CaptureArea) -> Bool {
        let a = result.area
        return a.x != currentArea.x || a.y != currentArea.y
            || a.width != currentArea.width || a.height != currentArea.height
    }
}
