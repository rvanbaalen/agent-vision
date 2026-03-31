import Foundation

public struct SessionColor: Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let hex: String

    public init(red: Double, green: Double, blue: Double, hex: String) {
        self.red = red
        self.green = green
        self.blue = blue
        self.hex = hex
    }
}

public enum SessionColors {
    public static let palette: [SessionColor] = [
        SessionColor(red: 0.231, green: 0.510, blue: 0.965, hex: "#3B82F6"), // Blue
        SessionColor(red: 0.133, green: 0.773, blue: 0.369, hex: "#22C55E"), // Green
        SessionColor(red: 0.961, green: 0.620, blue: 0.043, hex: "#F59E0B"), // Amber
        SessionColor(red: 0.937, green: 0.267, blue: 0.267, hex: "#EF4444"), // Red
        SessionColor(red: 0.659, green: 0.333, blue: 0.969, hex: "#A855F7"), // Purple
        SessionColor(red: 0.024, green: 0.714, blue: 0.831, hex: "#06B6D4"), // Cyan
        SessionColor(red: 0.925, green: 0.282, blue: 0.600, hex: "#EC4899"), // Pink
    ]

    public static func color(forIndex index: Int) -> SessionColor {
        palette[index % palette.count]
    }

    /// Returns the next color index to assign. Uses max(existing)+1 so colors
    /// don't get recycled when a session is removed.
    public static func nextColorIndex(existing: [Int]) -> Int {
        guard let maxIndex = existing.max() else { return 0 }
        return maxIndex + 1
    }
}
