import Foundation
import CoreGraphics
import ApplicationServices

public enum ElementDiscovery {

    /// Maximum depth for AX tree traversal.
    private static let maxDepth = 10
    /// Maximum total elements to collect.
    private static let maxElements = 500

    /// Actionable roles get priority in element ordering.
    private static let actionableRoles: Set<String> = [
        "AXButton", "AXLink", "AXTextField", "AXTextArea", "AXCheckBox",
        "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXMenuItem",
        "AXComboBox", "AXSlider", "AXIncrementor", "AXTab",
    ]

    /// Discover interactive elements within the selected area using the Accessibility API.
    public static func discover(area: CaptureArea) -> [DiscoveredElement] {
        guard let pid = findWindowOwnerPID(area: area) else { return [] }

        let appElement = AXUIElementCreateApplication(pid)
        var collected: [(role: String, label: String?, bounds: CGRect)] = []
        walkTree(element: appElement, area: area, depth: 0, collected: &collected)

        let deduped = deduplicateParentChild(collected)

        let sorted = deduped.sorted { a, b in
            let aActionable = actionableRoles.contains(a.role)
            let bActionable = actionableRoles.contains(b.role)
            if aActionable != bActionable { return aActionable }
            if a.bounds.minY != b.bounds.minY { return a.bounds.minY < b.bounds.minY }
            return a.bounds.minX < b.bounds.minX
        }

        return sorted.enumerated().map { idx, item in
            let relX = Double(item.bounds.midX) - area.x
            let relY = Double(item.bounds.midY) - area.y
            let relBoundsX = Double(item.bounds.minX) - area.x
            let relBoundsY = Double(item.bounds.minY) - area.y
            return DiscoveredElement(
                index: idx + 1,
                source: .accessibility,
                role: mapRole(item.role),
                label: item.label,
                center: Point(x: relX, y: relY),
                bounds: ElementBounds(x: relBoundsX, y: relBoundsY,
                                      width: Double(item.bounds.width), height: Double(item.bounds.height))
            )
        }
    }

    // MARK: - Window PID Lookup

    private static func findWindowOwnerPID(area: CaptureArea) -> pid_t? {
        let areaCenter = CGPoint(x: area.x + area.width / 2, y: area.y + area.height / 2)
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for window in windowList {
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let wx = boundsDict["X"] as? CGFloat,
                  let wy = boundsDict["Y"] as? CGFloat,
                  let ww = boundsDict["Width"] as? CGFloat,
                  let wh = boundsDict["Height"] as? CGFloat else { continue }

            let windowRect = CGRect(x: wx, y: wy, width: ww, height: wh)
            if windowRect.contains(areaCenter) {
                if let name = window[kCGWindowOwnerName as String] as? String,
                   name == "claude-vision-app" { continue }
                return pid
            }
        }
        return nil
    }

    // MARK: - AX Tree Walking

    private static func walkTree(element: AXUIElement, area: CaptureArea, depth: Int,
                                  collected: inout [(role: String, label: String?, bounds: CGRect)]) {
        guard depth < maxDepth, collected.count < maxElements else { return }

        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            walkChildren(of: element, area: area, depth: depth, collected: &collected)
            return
        }

        var hiddenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXHidden" as CFString, &hiddenRef) == .success,
           let hidden = hiddenRef as? Bool, hidden {
            return
        }

        if let bounds = getBounds(of: element) {
            let areaRect = CGRect(x: area.x, y: area.y, width: area.width, height: area.height)
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            if areaRect.contains(center) && bounds.width > 0 && bounds.height > 0 {
                let label = getLabel(of: element)
                collected.append((role: role, label: label, bounds: bounds))
            }
        }

        walkChildren(of: element, area: area, depth: depth, collected: &collected)
    }

    private static func walkChildren(of element: AXUIElement, area: CaptureArea, depth: Int,
                                      collected: inout [(role: String, label: String?, bounds: CGRect)]) {
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }

        for child in children {
            guard collected.count < maxElements else { return }
            walkTree(element: child, area: area, depth: depth + 1, collected: &collected)
        }
    }

    // MARK: - Attribute Helpers

    private static func getBounds(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
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

    // MARK: - Deduplication

    private static func deduplicateParentChild(_ elements: [(role: String, label: String?, bounds: CGRect)]) -> [(role: String, label: String?, bounds: CGRect)] {
        var seen: [String: Int] = [:]
        var result = elements

        for (i, el) in elements.enumerated() {
            let key = "\(Int(el.bounds.minX)),\(Int(el.bounds.minY)),\(Int(el.bounds.width)),\(Int(el.bounds.height))|\(el.label ?? "")"
            if let prevIdx = seen[key] {
                result[prevIdx].role = ""
            }
            seen[key] = i
        }

        return result.filter { !$0.role.isEmpty }
    }

    // MARK: - Role Mapping

    private static func mapRole(_ axRole: String) -> ElementRole {
        switch axRole {
        case "AXButton": return .button
        case "AXLink": return .link
        case "AXTextField", "AXTextArea", "AXComboBox": return .textField
        case "AXCheckBox", "AXRadioButton": return .checkbox
        case "AXMenuItem", "AXMenuButton": return .menuItem
        case "AXStaticText": return .staticText
        case "AXImage": return .image
        case "AXGroup", "AXList", "AXTable", "AXOutline", "AXToolbar",
             "AXScrollArea", "AXSplitGroup", "AXTabGroup": return .group
        default: return .unknown
        }
    }
}
