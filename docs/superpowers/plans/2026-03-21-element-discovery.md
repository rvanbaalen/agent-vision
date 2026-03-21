# Element Discovery System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace coordinate-guessing with Accessibility API + OCR element discovery, so Claude targets UI elements by index instead of estimating pixel positions.

**Architecture:** New shared library components (Element model, ElementDiscovery, TextDiscovery, ElementStore) handle element discovery and caching. The CLI gets a new `elements` command and an `--element N` flag on `click`. Element resolution happens CLI-side — the GUI/IPC layer is unchanged.

**Tech Stack:** Swift 6, macOS Accessibility API (AXUIElement), Vision framework (VNRecognizeTextRequest), CoreGraphics, ArgumentParser

**Spec:** `docs/superpowers/specs/2026-03-21-element-discovery-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/ClaudeVisionShared/Element.swift` | Create | Element model, JSON coding, role enum |
| `Sources/ClaudeVisionShared/ElementStore.swift` | Create | Read/write elements.json cache, stale detection |
| `Sources/ClaudeVisionShared/ElementDiscovery.swift` | Create | AX tree walking, element extraction, filtering |
| `Sources/ClaudeVisionShared/TextDiscovery.swift` | Create | Vision OCR, coordinate conversion, dedup |
| `Sources/ClaudeVisionShared/Capture.swift` | Modify | Add `captureWithElements` method for annotated screenshots |
| `Sources/ClaudeVisionShared/Config.swift` | Modify | Add `elementsFilePath` constant |
| `Sources/claude-vision/CLI.swift` | Modify | Add `Elements` command, modify `Click` for `--element` |
| `Tests/ClaudeVisionTests/ElementTests.swift` | Create | Element model tests |
| `Tests/ClaudeVisionTests/ElementStoreTests.swift` | Create | Store read/write/stale tests |
| `Tests/ClaudeVisionTests/TextDiscoveryTests.swift` | Create | Coordinate conversion + dedup tests |

---

### Task 1: Element Model + Config Path

**Files:**
- Create: `Sources/ClaudeVisionShared/Element.swift`
- Modify: `Sources/ClaudeVisionShared/Config.swift:8`
- Create: `Tests/ClaudeVisionTests/ElementTests.swift`

- [ ] **Step 1: Write failing tests for Element model**

Create `Tests/ClaudeVisionTests/ElementTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeVisionShared

@Suite struct ElementTests {

    @Test func elementEncodesToJSON() throws {
        let element = DiscoveredElement(
            index: 1,
            source: .accessibility,
            role: .button,
            label: "Submit",
            center: Point(x: 245, y: 162),
            bounds: ElementBounds(x: 200, y: 148, width: 90, height: 28)
        )
        let data = try JSONEncoder().encode(element)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["index"] as? Int == 1)
        #expect(json["source"] as? String == "accessibility")
        #expect(json["role"] as? String == "button")
        #expect(json["label"] as? String == "Submit")
    }

    @Test func boundsIntersectionArea() {
        let a = ElementBounds(x: 0, y: 0, width: 100, height: 100)
        let b = ElementBounds(x: 50, y: 50, width: 100, height: 100)
        #expect(a.intersectionArea(with: b) == 2500) // 50x50 overlap

        let c = ElementBounds(x: 200, y: 200, width: 50, height: 50)
        #expect(a.intersectionArea(with: c) == 0) // no overlap
    }

    @Test func boundsArea() {
        let b = ElementBounds(x: 10, y: 20, width: 80, height: 40)
        #expect(b.area == 3200)
    }

    @Test func displayLabelFallsBackForEmptyString() {
        let element = DiscoveredElement(
            index: 1, source: .accessibility, role: .button, label: "",
            center: Point(x: 50, y: 50), bounds: ElementBounds(x: 30, y: 40, width: 40, height: 20)
        )
        #expect(element.displayLabel == "(unlabeled button)")
    }

    @Test func elementRoundTrips() throws {
        let element = DiscoveredElement(
            index: 3,
            source: .ocr,
            role: .staticText,
            label: "Hello World",
            center: Point(x: 100, y: 50),
            bounds: ElementBounds(x: 80, y: 40, width: 40, height: 20)
        )
        let data = try JSONEncoder().encode(element)
        let decoded = try JSONDecoder().decode(DiscoveredElement.self, from: data)
        #expect(decoded.index == 3)
        #expect(decoded.source == .ocr)
        #expect(decoded.role == .staticText)
        #expect(decoded.label == "Hello World")
        #expect(decoded.center.x == 100)
        #expect(decoded.center.y == 50)
        #expect(decoded.bounds.width == 40)
    }

    @Test func scanResultEncodesElementCount() throws {
        let elements = [
            DiscoveredElement(index: 1, source: .accessibility, role: .button, label: "OK",
                              center: Point(x: 50, y: 50), bounds: ElementBounds(x: 30, y: 40, width: 40, height: 20)),
            DiscoveredElement(index: 2, source: .ocr, role: .staticText, label: "Cancel",
                              center: Point(x: 150, y: 50), bounds: ElementBounds(x: 130, y: 40, width: 40, height: 20)),
        ]
        let result = ElementScanResult(
            area: CaptureArea(x: 100, y: 200, width: 400, height: 300),
            elements: elements
        )
        let data = try JSONEncoder().encode(result)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["elementCount"] as? Int == 2)
        #expect((json["elements"] as? [[String: Any]])?.count == 2)
    }

    @Test func allRolesEncodeToExpectedStrings() throws {
        let roles: [(ElementRole, String)] = [
            (.button, "button"), (.link, "link"), (.textField, "textField"),
            (.checkbox, "checkbox"), (.menuItem, "menuItem"), (.staticText, "staticText"),
            (.image, "image"), (.group, "group"), (.unknown, "unknown"),
        ]
        for (role, expected) in roles {
            let data = try JSONEncoder().encode(role)
            let str = String(data: data, encoding: .utf8)!
            #expect(str == "\"\(expected)\"")
        }
    }

    @Test func unlabeledElementGetsDefaultLabel() {
        let element = DiscoveredElement(
            index: 1, source: .accessibility, role: .button, label: nil,
            center: Point(x: 50, y: 50), bounds: ElementBounds(x: 30, y: 40, width: 40, height: 20)
        )
        #expect(element.displayLabel == "(unlabeled button)")
    }

    @Test func labeledElementUsesLabel() {
        let element = DiscoveredElement(
            index: 1, source: .accessibility, role: .button, label: "Submit",
            center: Point(x: 50, y: 50), bounds: ElementBounds(x: 30, y: 40, width: 40, height: 20)
        )
        #expect(element.displayLabel == "Submit")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ElementTests 2>&1 | head -20`
Expected: Compilation failure — `DiscoveredElement`, `ElementBounds`, etc. not defined.

- [ ] **Step 3: Add elementsFilePath to Config**

In `Sources/ClaudeVisionShared/Config.swift`, add after line 8:

```swift
    public static let elementsFilePath = stateDirectory.appendingPathComponent("elements.json")
```

- [ ] **Step 4: Create Element.swift with model types**

Create `Sources/ClaudeVisionShared/Element.swift`:

```swift
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ElementTests 2>&1 | tail -20`
Expected: All 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeVisionShared/Element.swift Sources/ClaudeVisionShared/Config.swift Tests/ClaudeVisionTests/ElementTests.swift
git commit -m "feat: add Element model and Config.elementsFilePath"
```

---

### Task 2: ElementStore (Cache Read/Write/Stale Detection)

**Files:**
- Create: `Sources/ClaudeVisionShared/ElementStore.swift`
- Create: `Tests/ClaudeVisionTests/ElementStoreTests.swift`

- [ ] **Step 1: Write failing tests for ElementStore**

Create `Tests/ClaudeVisionTests/ElementStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeVisionShared

@Suite struct ElementStoreTests {

    private func tmpDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("element-store-test-\(UUID().uuidString)")
    }

    private func sampleResult(area: CaptureArea? = nil) -> ElementScanResult {
        let a = area ?? CaptureArea(x: 100, y: 200, width: 800, height: 600)
        return ElementScanResult(area: a, elements: [
            DiscoveredElement(index: 1, source: .accessibility, role: .button, label: "OK",
                              center: Point(x: 50, y: 50), bounds: ElementBounds(x: 30, y: 40, width: 40, height: 20)),
        ])
    }

    @Test func writeAndReadRoundTrips() throws {
        let dir = tmpDir()
        let file = dir.appendingPathComponent("elements.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = sampleResult()
        try ElementStore.write(result, to: file, createDirectory: dir)

        let read = try ElementStore.read(from: file)
        #expect(read != nil)
        #expect(read!.elementCount == 1)
        #expect(read!.elements[0].label == "OK")
    }

    @Test func readReturnsNilWhenNoFile() throws {
        let file = tmpDir().appendingPathComponent("nonexistent.json")
        let read = try ElementStore.read(from: file)
        #expect(read == nil)
    }

    @Test func lookupFindsElementByIndex() throws {
        let result = sampleResult()
        let element = ElementStore.lookup(index: 1, in: result)
        #expect(element != nil)
        #expect(element!.label == "OK")
    }

    @Test func lookupReturnsNilForOutOfRange() throws {
        let result = sampleResult()
        #expect(ElementStore.lookup(index: 0, in: result) == nil)
        #expect(ElementStore.lookup(index: 2, in: result) == nil)
        #expect(ElementStore.lookup(index: 99, in: result) == nil)
    }

    @Test func staleCheckDetectsAreaChange() throws {
        let result = sampleResult(area: CaptureArea(x: 100, y: 200, width: 800, height: 600))
        let currentArea = CaptureArea(x: 150, y: 200, width: 800, height: 600)
        #expect(ElementStore.isStale(result, currentArea: currentArea) == true)
    }

    @Test func staleCheckPassesWhenAreaMatches() throws {
        let area = CaptureArea(x: 100, y: 200, width: 800, height: 600)
        let result = sampleResult(area: area)
        #expect(ElementStore.isStale(result, currentArea: area) == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ElementStoreTests 2>&1 | head -20`
Expected: Compilation failure — `ElementStore` not defined.

- [ ] **Step 3: Create ElementStore.swift**

Create `Sources/ClaudeVisionShared/ElementStore.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ElementStoreTests 2>&1 | tail -20`
Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeVisionShared/ElementStore.swift Tests/ClaudeVisionTests/ElementStoreTests.swift
git commit -m "feat: add ElementStore for scan cache read/write/stale detection"
```

---

### Task 3: ElementDiscovery (Accessibility API)

**Files:**
- Create: `Sources/ClaudeVisionShared/ElementDiscovery.swift`

Note: AX APIs require accessibility permissions and a running app, so they can't be unit tested in CI. This task is implementation-only with manual verification.

- [ ] **Step 1: Create ElementDiscovery.swift**

Create `Sources/ClaudeVisionShared/ElementDiscovery.swift`:

```swift
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
    /// - Parameter area: The selected capture area (in global screen coords).
    /// - Returns: Array of discovered elements with area-relative coordinates.
    public static func discover(area: CaptureArea) -> [DiscoveredElement] {
        guard let pid = findWindowOwnerPID(area: area) else { return [] }

        let appElement = AXUIElementCreateApplication(pid)
        var collected: [(role: String, label: String?, bounds: CGRect)] = []
        walkTree(element: appElement, area: area, depth: 0, collected: &collected)

        // Deduplicate: if parent and child have same bounds+label, we kept both — remove parent
        let deduped = deduplicateParentChild(collected)

        // Sort: actionable elements first, then by position (top-to-bottom, left-to-right)
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
        // Find topmost window whose bounds contain the area center
        for window in windowList {
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let wx = boundsDict["X"] as? CGFloat,
                  let wy = boundsDict["Y"] as? CGFloat,
                  let ww = boundsDict["Width"] as? CGFloat,
                  let wh = boundsDict["Height"] as? CGFloat else { continue }

            let windowRect = CGRect(x: wx, y: wy, width: ww, height: wh)
            if windowRect.contains(areaCenter) {
                // Skip the claude-vision-app itself (the toolbar/border windows)
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

        // Get role
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            // Still try children even if this element has no role
            walkChildren(of: element, area: area, depth: depth, collected: &collected)
            return
        }

        // Check hidden
        var hiddenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, "AXHidden" as CFString, &hiddenRef) == .success,
           let hidden = hiddenRef as? Bool, hidden {
            return // Skip hidden elements and their subtrees
        }

        // Get position and size
        if let bounds = getBounds(of: element) {
            let areaRect = CGRect(x: area.x, y: area.y, width: area.width, height: area.height)

            // Only include if center is inside the capture area
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
        guard let posVal = posRef as? AXValue,
              let sizeVal = sizeRef as? AXValue,
              AXValueGetValue(posVal, .cgPoint, &position),
              AXValueGetValue(sizeVal, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private static func getLabel(of element: AXUIElement) -> String? {
        // Try title first, then description, then value
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
        // If two elements have identical bounds and label, keep only the last one (deeper = child)
        var seen: [String: Int] = [:]
        var result = elements

        for (i, el) in elements.enumerated() {
            let key = "\(Int(el.bounds.minX)),\(Int(el.bounds.minY)),\(Int(el.bounds.width)),\(Int(el.bounds.height))|\(el.label ?? "")"
            if let prevIdx = seen[key] {
                result[prevIdx].role = "" // mark for removal
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
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeVisionShared/ElementDiscovery.swift
git commit -m "feat: add ElementDiscovery with AX tree walking"
```

---

### Task 4: TextDiscovery (Vision OCR)

**Files:**
- Create: `Sources/ClaudeVisionShared/TextDiscovery.swift`
- Create: `Tests/ClaudeVisionTests/TextDiscoveryTests.swift`

- [ ] **Step 1: Write failing tests for coordinate conversion and dedup**

Create `Tests/ClaudeVisionTests/TextDiscoveryTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeVisionShared

@Suite struct TextDiscoveryTests {

    @Test func visionCoordsConvertToAreaRelative() {
        // Vision: normalized (0-1), bottom-left origin
        // Area: pixel coords, top-left origin
        let areaWidth = 800.0
        let areaHeight = 600.0

        // A text observation at normalized center (0.5, 0.5) should map to area center
        let result = TextDiscovery.convertVisionBounds(
            midX: 0.5, midY: 0.5,
            x: 0.4, y: 0.4, width: 0.2, height: 0.2,
            areaWidth: areaWidth, areaHeight: areaHeight, scaleFactor: 1.0
        )
        #expect(result.center.x == 400.0)
        #expect(result.center.y == 300.0) // 600 - (0.5 * 600) = 300
        #expect(result.bounds.x == 320.0) // 0.4 * 800
        #expect(result.bounds.width == 160.0) // 0.2 * 800
    }

    @Test func visionCoordsHandleRetinaScaling() {
        // At 2x Retina, the CGImage is 1600px wide but area is 800pt
        let result = TextDiscovery.convertVisionBounds(
            midX: 0.5, midY: 0.5,
            x: 0.4, y: 0.4, width: 0.2, height: 0.2,
            areaWidth: 1600.0, areaHeight: 1200.0, scaleFactor: 2.0
        )
        // Should be in screen points, not pixels
        #expect(result.center.x == 400.0) // (0.5 * 1600) / 2
        #expect(result.center.y == 300.0) // (1200 - 0.5 * 1200) / 2
    }

    @Test func visionCoordsTopLeftOrigin() {
        // Text near top of screen: Vision midY ~0.9 (near top in bottom-left coords)
        let result = TextDiscovery.convertVisionBounds(
            midX: 0.1, midY: 0.9,
            x: 0.05, y: 0.85, width: 0.1, height: 0.1,
            areaWidth: 800.0, areaHeight: 600.0, scaleFactor: 1.0
        )
        // In top-left coords, y should be near 0
        #expect(result.center.x == 80.0) // 0.1 * 800
        #expect(result.center.y == 60.0) // 600 - (0.9 * 600) = 60
    }

    @Test func shouldDedup_overlappingWithMatchingLabel() {
        let ocrBounds = ElementBounds(x: 100, y: 100, width: 80, height: 20)
        let axElement = DiscoveredElement(
            index: 1, source: .accessibility, role: .button, label: "Submit",
            center: Point(x: 140, y: 110),
            bounds: ElementBounds(x: 95, y: 95, width: 90, height: 30)
        )
        // OCR text "Submit" overlaps >50% with AX element labeled "Submit"
        let result = TextDiscovery.shouldDeduplicate(ocrText: "Submit", ocrBounds: ocrBounds, against: [axElement])
        #expect(result == true)
    }

    @Test func shouldNotDedup_differentLabel() {
        let ocrBounds = ElementBounds(x: 100, y: 100, width: 80, height: 20)
        let axElement = DiscoveredElement(
            index: 1, source: .accessibility, role: .button, label: "Cancel",
            center: Point(x: 140, y: 110),
            bounds: ElementBounds(x: 95, y: 95, width: 90, height: 30)
        )
        let result = TextDiscovery.shouldDeduplicate(ocrText: "Submit", ocrBounds: ocrBounds, against: [axElement])
        #expect(result == false)
    }

    @Test func shouldNotDedup_noOverlap() {
        let ocrBounds = ElementBounds(x: 500, y: 500, width: 80, height: 20)
        let axElement = DiscoveredElement(
            index: 1, source: .accessibility, role: .button, label: "Submit",
            center: Point(x: 140, y: 110),
            bounds: ElementBounds(x: 95, y: 95, width: 90, height: 30)
        )
        let result = TextDiscovery.shouldDeduplicate(ocrText: "Submit", ocrBounds: ocrBounds, against: [axElement])
        #expect(result == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TextDiscoveryTests 2>&1 | head -20`
Expected: Compilation failure — `TextDiscovery` not defined.

- [ ] **Step 3: Create TextDiscovery.swift**

Create `Sources/ClaudeVisionShared/TextDiscovery.swift`:

```swift
import Foundation
import CoreGraphics
import Vision

public enum TextDiscovery {

    /// Result of converting Vision coordinates to area-relative coordinates.
    public struct ConvertedBounds: Sendable {
        public let center: Point
        public let bounds: ElementBounds
    }

    /// Convert Vision normalized coordinates (0-1, bottom-left origin) to area-relative screen points.
    public static func convertVisionBounds(
        midX: Double, midY: Double,
        x: Double, y: Double, width: Double, height: Double,
        areaWidth: Double, areaHeight: Double, scaleFactor: Double
    ) -> ConvertedBounds {
        let centerX = (midX * areaWidth) / scaleFactor
        let centerY = (areaHeight - midY * areaHeight) / scaleFactor
        let boundsX = (x * areaWidth) / scaleFactor
        let boundsY = (areaHeight - (y + height) * areaHeight) / scaleFactor
        let boundsW = (width * areaWidth) / scaleFactor
        let boundsH = (height * areaHeight) / scaleFactor

        return ConvertedBounds(
            center: Point(x: centerX, y: centerY),
            bounds: ElementBounds(x: boundsX, y: boundsY, width: boundsW, height: boundsH)
        )
    }

    /// Check if an OCR text result should be deduplicated against existing AX elements.
    /// Returns true if any AX element overlaps >50% of the OCR bounds AND its label contains the OCR text.
    public static func shouldDeduplicate(ocrText: String, ocrBounds: ElementBounds,
                                          against axElements: [DiscoveredElement]) -> Bool {
        let ocrLower = ocrText.lowercased()
        for ax in axElements {
            guard let axLabel = ax.label?.lowercased(), axLabel.contains(ocrLower) else { continue }
            let overlap = ocrBounds.intersectionArea(with: ax.bounds)
            if ocrBounds.area > 0 && overlap / ocrBounds.area > 0.5 {
                return true
            }
        }
        return false
    }

    /// Run OCR on a captured image and return discovered text elements.
    /// - Parameters:
    ///   - image: CGImage of the captured area (may be at Retina resolution).
    ///   - areaWidth: Width of the captured area in screen points.
    ///   - areaHeight: Height of the captured area in screen points.
    ///   - existingElements: AX elements to deduplicate against.
    ///   - startIndex: 1-based index to start numbering from.
    /// - Returns: Array of discovered text elements with area-relative coordinates.
    public static func discover(image: CGImage, areaWidth: Double, areaHeight: Double,
                                 existingElements: [DiscoveredElement], startIndex: Int) -> [DiscoveredElement] {
        let scaleFactor = Double(image.width) / areaWidth
        let imageWidth = Double(image.width)
        let imageHeight = Double(image.height)

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else { return [] }

        var results: [DiscoveredElement] = []
        var currentIndex = startIndex

        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            let box = observation.boundingBox

            let converted = convertVisionBounds(
                midX: box.midX, midY: box.midY,
                x: box.origin.x, y: box.origin.y, width: box.width, height: box.height,
                areaWidth: imageWidth, areaHeight: imageHeight, scaleFactor: scaleFactor
            )

            // Skip if this duplicates an existing AX element
            if shouldDeduplicate(ocrText: text, ocrBounds: converted.bounds, against: existingElements) {
                continue
            }

            results.append(DiscoveredElement(
                index: currentIndex,
                source: .ocr,
                role: .staticText,
                label: text,
                center: converted.center,
                bounds: converted.bounds
            ))
            currentIndex += 1
        }

        return results
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TextDiscoveryTests 2>&1 | tail -20`
Expected: All 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeVisionShared/TextDiscovery.swift Tests/ClaudeVisionTests/TextDiscoveryTests.swift
git commit -m "feat: add TextDiscovery with Vision OCR and dedup logic"
```

---

### Task 5: Annotated Screenshot (captureWithElements)

**Files:**
- Modify: `Sources/ClaudeVisionShared/Capture.swift`

Note: This must come before the CLI Elements command (Task 6) which calls `captureWithElements`.

---

### Task 6: CLI — Elements Command

**Files:**
- Modify: `Sources/claude-vision/CLI.swift:6,10` (subcommands list)

- [ ] **Step 1: Add Elements command to CLI.swift**

In `Sources/claude-vision/CLI.swift`, change line 10 to add `Elements` to the subcommands:

```swift
        subcommands: [Start.self, Wait.self, Capture.self, Calibrate.self, Preview.self, Stop.self, Control.self, Elements.self]
```

Then add the `Elements` command after the `Control` extension (at the end of the file):

```swift
struct Elements: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Discover interactive elements in the selected area"
    )

    @Flag(name: .long, help: "Save annotated screenshot with numbered badges")
    var annotated: Bool = false

    @Option(name: .long, help: "Output file path for annotated screenshot")
    var output: String?

    func run() throws {
        let area = try requireArea()

        // Run accessibility discovery
        let axElements = ElementDiscovery.discover(area: area)

        // Capture image for OCR
        let rect = CGRect(x: area.x, y: area.y, width: area.width, height: area.height)
        var ocrElements: [DiscoveredElement] = []
        if let image = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution) {
            ocrElements = TextDiscovery.discover(
                image: image,
                areaWidth: area.width,
                areaHeight: area.height,
                existingElements: axElements,
                startIndex: axElements.count + 1
            )
        }

        // Log warning if AX returned nothing (possible permission issue)
        if axElements.isEmpty {
            fputs("Warning: No elements found via Accessibility API. Check permissions or try a different area.\n", stderr)
        }

        let allElements = axElements + ocrElements
        let result = ElementScanResult(area: area, elements: allElements)

        // Write cache
        try ElementStore.write(result, to: Config.elementsFilePath, createDirectory: Config.stateDirectory)

        // Output JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(result)
        print(String(data: json, encoding: .utf8)!)

        // Annotated screenshot if requested
        if annotated {
            let outputPath: String
            if let p = output {
                outputPath = p
            } else {
                outputPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent("claude-vision-elements-\(Int(Date().timeIntervalSince1970)).png").path
            }
            try ScreenCapture.captureWithElements(area: area, elements: allElements, to: URL(fileURLWithPath: outputPath))
            fputs("Annotated screenshot: \(outputPath)\n", stderr)
        }
    }
}
```

Also add `import CoreGraphics` at the top of CLI.swift (after line 1) if not already present.

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds (captureWithElements was added in Task 5).

- [ ] **Step 3: Commit**

```bash
git add Sources/claude-vision/CLI.swift
git commit -m "feat: add Elements command to CLI"
```

---

### Task 7: CLI — Modify Click for --element

**Files:**
- Modify: `Sources/claude-vision/CLI.swift:272-281` (Click command)

- [ ] **Step 1: Modify the Click command to accept --element**

Replace the `Click` struct inside the `Control` extension:

```swift
    struct Click: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Left-click at a position")

        @Option(name: .long, help: "Position as X,Y relative to area top-left")
        var at: String?

        @Option(name: .long, help: "Element index from last 'elements' scan")
        var element: Int?

        func run() throws {
            let area = try requireArea()

            let point: Point
            if let elementIndex = element {
                guard at == nil else {
                    fputs("Specify either --at or --element, not both.\n", stderr)
                    throw ExitCode.failure
                }
                guard let scanResult = try ElementStore.read(from: Config.elementsFilePath) else {
                    fputs("No element scan found. Run 'claude-vision elements' first.\n", stderr)
                    throw ExitCode.failure
                }
                if ElementStore.isStale(scanResult, currentArea: area) {
                    fputs("Stale scan: capture area changed since last scan. Run 'claude-vision elements' again.\n", stderr)
                    throw ExitCode.failure
                }
                guard let el = ElementStore.lookup(index: elementIndex, in: scanResult) else {
                    fputs("Element \(elementIndex) not found. Last scan found \(scanResult.elementCount) elements (1-\(scanResult.elementCount)).\n", stderr)
                    throw ExitCode.failure
                }
                point = el.center
            } else if let atStr = at {
                point = try parsePoint(atStr)
            } else {
                fputs("Specify --at X,Y or --element N.\n", stderr)
                throw ExitCode.failure
            }

            try sendAction(.click(at: point), area: area)
        }
    }
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/claude-vision/CLI.swift
git commit -m "feat: add --element flag to click command for element-based targeting"
```

---

- [ ] **Step 1: Add captureWithElements method to Capture.swift**

Add after the `captureWithPreview` method (after line 173):

```swift
    /// Capture with numbered badges overlaid on discovered elements.
    public static func captureWithElements(area: CaptureArea, elements: [DiscoveredElement], to outputURL: URL) throws {
        let rect = CGRect(x: area.x, y: area.y, width: area.width, height: area.height)

        guard let image = CGWindowListCreateImage(
            rect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution
        ) else {
            throw CaptureError.captureFailedNoImage
        }

        let pw = image.width
        let ph = image.height
        let scaleX = CGFloat(pw) / CGFloat(area.width)
        let scaleY = CGFloat(ph) / CGFloat(area.height)

        guard let ctx = createContext(width: pw, height: ph) else {
            throw CaptureError.cannotCreateDestination(outputURL.path)
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: pw, height: ph))

        let badgeSize: CGFloat = 20 * scaleX
        let fontSize: CGFloat = 11 * scaleX
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)

        // Track badge positions for collision avoidance
        var placedBadges: [CGRect] = []

        for element in elements {
            let blue = CGColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0)
            let orange = CGColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
            let badgeColor = element.source == .accessibility ? blue : orange

            // Element bounds in pixel coords
            let bx = CGFloat(element.bounds.x) * scaleX
            let by = CGFloat(ph) - CGFloat(element.bounds.y + element.bounds.height) * scaleY
            let bw = CGFloat(element.bounds.width) * scaleX
            let bh = CGFloat(element.bounds.height) * scaleY

            // Draw element bounds outline
            ctx.setStrokeColor(badgeColor.copy(alpha: 0.4)!)
            ctx.setLineWidth(1.5 * scaleX)
            ctx.stroke(CGRect(x: bx, y: by, width: bw, height: bh))

            // Badge position: top-left of element, with collision avoidance
            var badgeX = bx
            var badgeY = by + bh - badgeSize // top-left in flipped coords
            let candidateRect = CGRect(x: badgeX, y: badgeY, width: badgeSize, height: badgeSize)

            // Simple collision avoidance: shift right, then down
            var finalRect = candidateRect
            for placed in placedBadges {
                if finalRect.intersects(placed) {
                    finalRect.origin.x = placed.maxX + 2 * scaleX
                    if finalRect.maxX > CGFloat(pw) {
                        finalRect.origin.x = bx
                        finalRect.origin.y -= badgeSize + 2 * scaleX
                    }
                }
            }
            placedBadges.append(finalRect)

            // Draw badge background
            let badgePath = CGPath(roundedRect: finalRect, cornerWidth: 4 * scaleX, cornerHeight: 4 * scaleX, transform: nil)
            ctx.setFillColor(badgeColor)
            ctx.addPath(badgePath)
            ctx.fillPath()

            // Draw badge number
            let numberStr = "\(element.index)" as CFString
            let attrs = [kCTFontAttributeName: font,
                         kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1)] as CFDictionary
            let attrStr = CFAttributedStringCreate(nil, numberStr, attrs)!
            let line = CTLineCreateWithAttributedString(attrStr)
            let textBounds = CTLineGetBoundsWithOptions(line, [])

            ctx.saveGState()
            ctx.textPosition = CGPoint(
                x: finalRect.midX - textBounds.width / 2,
                y: finalRect.midY - textBounds.height / 2
            )
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }

        guard let result = ctx.makeImage() else {
            throw CaptureError.writeFailed(outputURL.path)
        }
        try saveImage(result, to: outputURL)
    }
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeVisionShared/Capture.swift
git commit -m "feat: add annotated screenshot with numbered element badges"
```

---

### Task 8: Integration Test — Full Build + Manual Verification

- [ ] **Step 1: Run all tests**

Run: `swift test 2>&1 | tail -30`
Expected: All tests pass (Element, ElementStore, TextDiscovery, plus all existing tests).

- [ ] **Step 2: Build release**

Run: `swift build -c release 2>&1 | tail -10`
Expected: Release build succeeds.

- [ ] **Step 3: Manual smoke test**

If claude-vision is installed, run these to verify end-to-end:

```bash
# Start and select an area, then:
claude-vision elements
# Should output JSON with discovered elements

claude-vision elements --annotated
# Should output JSON + path to annotated screenshot

claude-vision control click --element 1
# Should click center of element 1

# Error cases:
claude-vision control click --element 999
# Should print: "Element 999 not found..."

claude-vision control click
# Should print: "Specify --at X,Y or --element N."

claude-vision control click --at 50,50 --element 1
# Should print: "Specify either --at or --element, not both."
```

- [ ] **Step 4: Commit any fixes from smoke testing**

```bash
git add -A
git commit -m "fix: address issues found in manual smoke testing"
```

(Skip if no fixes needed.)
