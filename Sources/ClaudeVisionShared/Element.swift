import Foundation

public enum ElementSource: String, Codable, Sendable {
    case accessibility
    case ocr
}

public enum ElementRole: String, Codable, Sendable {
    case button
    case link
    case textField
    case checkbox
    case menuItem
    case staticText
    case image
    case group
    case unknown
}

public struct ElementBounds: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    /// Area of this bounding rect.
    public var area: Double { width * height }

    /// Returns the intersection area with another bounds rect.
    public func intersectionArea(with other: ElementBounds) -> Double {
        let overlapX = max(0, min(x + width, other.x + other.width) - max(x, other.x))
        let overlapY = max(0, min(y + height, other.y + other.height) - max(y, other.y))
        return overlapX * overlapY
    }
}

public struct DiscoveredElement: Codable, Sendable {
    public let index: Int
    public let source: ElementSource
    public let role: ElementRole
    public let label: String?
    public let center: Point
    public let bounds: ElementBounds

    public init(index: Int, source: ElementSource, role: ElementRole, label: String?,
                center: Point, bounds: ElementBounds) {
        self.index = index; self.source = source; self.role = role
        self.label = label; self.center = center; self.bounds = bounds
    }

    /// Label for display — uses actual label or falls back to "(unlabeled <role>)".
    public var displayLabel: String {
        if let label, !label.isEmpty { return label }
        return "(unlabeled \(role.rawValue))"
    }
}

public struct ElementScanResult: Codable, Sendable {
    public let area: CaptureArea
    public let elementCount: Int
    public let elements: [DiscoveredElement]
    public let timestamp: Int

    public init(area: CaptureArea, elements: [DiscoveredElement]) {
        self.area = area
        self.elementCount = elements.count
        self.elements = elements
        self.timestamp = Int(Date().timeIntervalSince1970)
    }
}
