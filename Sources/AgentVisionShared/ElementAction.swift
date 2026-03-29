import Foundation
import CoreGraphics
import ApplicationServices

public enum ElementActionError: Error, CustomStringConvertible {
    case windowNotFound
    case elementNotFound(index: Int)
    case actionFailed(index: Int)
    case notTextField(index: Int, role: String)
    case setValueFailed(index: Int)

    public var description: String {
        switch self {
        case .windowNotFound:
            return "No window found under the selected area."
        case .elementNotFound(let index):
            return "Element \(index) not found in current UI. Run 'agent-vision elements' again."
        case .actionFailed(let index):
            return "Failed to perform action on element \(index). The element may not be actionable."
        case .notTextField(let index, let role):
            return "Element \(index) is a \(role), not a text field."
        case .setValueFailed(let index):
            return "Failed to set text on element \(index)."
        }
    }
}

public enum ElementAction {

    /// Bounds tolerance in points for re-matching elements after a scan.
    private static let boundsTolerance: Double = 2.0

    /// Maximum depth for AX tree traversal (matches ElementDiscovery).
    private static let maxDepth = 25
    /// Maximum total elements to visit (matches ElementDiscovery).
    private static let maxElements = 1000

    /// Press (click) an element by re-finding it in the AX tree. Focus-free — does not move cursor.
    public static func press(element: DiscoveredElement, area: CaptureArea) throws {
        let axElement = try findAXElement(element: element, area: area)

        let result = AXUIElementPerformAction(axElement, kAXPressAction as CFString)
        guard result == .success else {
            throw ElementActionError.actionFailed(index: element.index)
        }
    }

    /// Focus and set text on a text field element. Focus-free — does not move cursor.
    public static func setText(_ text: String, element: DiscoveredElement, area: CaptureArea) throws {
        // Verify it's a text-like element
        guard element.role == .textField else {
            throw ElementActionError.notTextField(index: element.index, role: element.role.rawValue)
        }

        let axElement = try findAXElement(element: element, area: area)

        // Focus the element first
        _ = AXUIElementSetAttributeValue(axElement, kAXFocusedAttribute as CFString, true as CFTypeRef)
        // Focus may fail on some elements but text setting might still work — don't bail here

        // Set the value
        let valueResult = AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, text as CFTypeRef)
        guard valueResult == .success else {
            throw ElementActionError.setValueFailed(index: element.index)
        }
    }

    // MARK: - Element Re-matching

    /// Re-walk the AX tree to find the AXUIElement matching the cached element metadata.
    private static func findAXElement(element: DiscoveredElement, area: CaptureArea) throws -> AXUIElement {
        guard let pid = ElementDiscovery.findWindowOwnerPID(area: area) else {
            throw ElementActionError.windowNotFound
        }

        let appElement = AXUIElementCreateApplication(pid)

        // Target bounds in absolute screen coordinates
        let targetBounds = CGRect(
            x: area.x + element.bounds.x,
            y: area.y + element.bounds.y,
            width: element.bounds.width,
            height: element.bounds.height
        )

        var match: AXUIElement?
        walkForMatch(element: appElement, targetBounds: targetBounds, targetLabel: element.label,
                     depth: 0, visited: 0, match: &match)

        guard let found = match else {
            throw ElementActionError.elementNotFound(index: element.index)
        }
        return found
    }

    private static func walkForMatch(element: AXUIElement, targetBounds: CGRect, targetLabel: String?,
                                      depth: Int, visited: Int, match: inout AXUIElement?) {
        guard match == nil, depth < maxDepth, visited < maxElements else { return }

        // Check this element's bounds
        if let bounds = getBounds(of: element) {
            if boundsMatch(bounds, targetBounds) && labelMatches(element, targetLabel) {
                match = element
                return
            }
        }

        // Walk children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }

        var count = visited
        for child in children {
            guard match == nil else { return }
            count += 1
            guard count < maxElements else { return }
            walkForMatch(element: child, targetBounds: targetBounds, targetLabel: targetLabel,
                         depth: depth + 1, visited: count, match: &match)
        }
    }

    // MARK: - Matching Helpers

    private static func boundsMatch(_ actual: CGRect, _ target: CGRect) -> Bool {
        let tol = boundsTolerance
        return abs(actual.minX - target.minX) <= tol
            && abs(actual.minY - target.minY) <= tol
            && abs(actual.width - target.width) <= tol
            && abs(actual.height - target.height) <= tol
    }

    private static func labelMatches(_ element: AXUIElement, _ targetLabel: String?) -> Bool {
        let actual = getLabel(of: element)
        if targetLabel == nil && actual == nil { return true }
        return actual == targetLabel
    }

    private static func getBounds(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        // Verify CFTypeRef is actually an AXValue before force-casting
        guard CFGetTypeID(posRef!) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef!) == AXValueGetTypeID() else {
            return nil
        }
        let posVal = posRef as! AXValue
        let sizeVal = sizeRef as! AXValue
        guard AXValueGetValue(posVal, .cgPoint, &position),
              AXValueGetValue(sizeVal, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private static func getLabel(of element: AXUIElement) -> String? {
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success,
               let str = ref as? String, !str.isEmpty {
                return str
            }
        }
        return nil
    }
}
