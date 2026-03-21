# Input Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add input control actions (click, scroll, drag, type, key press) to Claude Vision so Claude can interact with on-screen UI within the selected area.

**Architecture:** The CLI writes action requests as JSON files. The GUI app watches for these files, executes the corresponding CGEvent input, shows visual feedback, and writes a result file. All coordinates are relative to the selected area and bounds-checked before execution.

**Tech Stack:** Swift 6, AppKit, CGEvent API, DispatchSource (file watching), ArgumentParser

---

## File Structure

```
Sources/
├── claude-vision/
│   └── CLI.swift                      # Modify: add Control subcommand group
├── claude-vision-app/
│   ├── AppDelegate.swift              # Modify: wire up ActionWatcher
│   ├── ActionWatcher.swift            # NEW: file watcher + CGEvent dispatch
│   ├── ActionFeedbackWindow.swift     # NEW: visual ripple overlay
│   └── (existing files unchanged)
└── ClaudeVisionShared/
    ├── Action.swift                   # NEW: Codable action types, validation, file I/O
    ├── KeyMapping.swift               # NEW: key name → virtual key code mapping
    └── Config.swift                   # Modify: add action/result file paths

Tests/
└── ClaudeVisionTests/
    ├── ActionTests.swift              # NEW: action encoding, bounds validation
    └── KeyMappingTests.swift          # NEW: key parsing and mapping
```

**Key decisions:**
- Action types and bounds validation live in `ClaudeVisionShared` so both CLI and GUI share them
- Key mapping is its own file — it's a substantial lookup table
- ActionWatcher handles both file watching and CGEvent execution (single responsibility: "receive and execute actions")
- ActionFeedbackWindow is separate from ActionWatcher (display vs. execution)

---

### Task 1: Action Types + Config Paths (TDD)

**Files:**
- Create: `Sources/ClaudeVisionShared/Action.swift`
- Modify: `Sources/ClaudeVisionShared/Config.swift`
- Create: `Tests/ClaudeVisionTests/ActionTests.swift`

- [ ] **Step 1: Write failing tests for action types**

`Tests/ClaudeVisionTests/ActionTests.swift`:
```swift
import XCTest
@testable import ClaudeVisionShared

final class ActionTests: XCTestCase {

    // MARK: - Encoding

    func testClickActionEncodes() throws {
        let action = ActionRequest.click(at: Point(x: 150, y: 300))
        let data = try JSONEncoder().encode(action)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["action"] as? String, "click")
    }

    func testTypeActionEncodes() throws {
        let action = ActionRequest.type(text: "hello")
        let data = try JSONEncoder().encode(action)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["action"] as? String, "type")
        XCTAssertEqual(json["text"] as? String, "hello")
    }

    func testKeyActionEncodes() throws {
        let action = ActionRequest.key(key: "cmd+a")
        let data = try JSONEncoder().encode(action)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["action"] as? String, "key")
        XCTAssertEqual(json["key"] as? String, "cmd+a")
    }

    func testScrollActionEncodes() throws {
        let action = ActionRequest.scroll(delta: Delta(dx: 0, dy: -100), at: Point(x: 200, y: 300))
        let data = try JSONEncoder().encode(action)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["action"] as? String, "scroll")
    }

    func testDragActionEncodes() throws {
        let action = ActionRequest.drag(from: Point(x: 150, y: 400), to: Point(x: 150, y: 100))
        let data = try JSONEncoder().encode(action)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["action"] as? String, "drag")
    }

    func testActionRoundTrips() throws {
        let action = ActionRequest.click(at: Point(x: 42, y: 99))
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(ActionRequest.self, from: data)
        if case .click(let pt) = decoded {
            XCTAssertEqual(pt.x, 42)
            XCTAssertEqual(pt.y, 99)
        } else {
            XCTFail("Expected click action")
        }
    }

    func testResultEncodes() throws {
        let result = ActionResult(success: true, message: "Clicked at (150, 300)")
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(ActionResult.self, from: data)
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.message, "Clicked at (150, 300)")
    }

    // MARK: - Bounds Checking

    func testBoundsCheckPassesForValidCoordinates() {
        let area = CaptureArea(x: 100, y: 200, width: 400, height: 600)
        XCTAssertNil(ActionRequest.click(at: Point(x: 0, y: 0)).boundsError(for: area))
        XCTAssertNil(ActionRequest.click(at: Point(x: 399, y: 599)).boundsError(for: area))
        XCTAssertNil(ActionRequest.click(at: Point(x: 200, y: 300)).boundsError(for: area))
    }

    func testBoundsCheckFailsForOutOfBounds() {
        let area = CaptureArea(x: 100, y: 200, width: 400, height: 600)
        XCTAssertNotNil(ActionRequest.click(at: Point(x: 400, y: 0)).boundsError(for: area))
        XCTAssertNotNil(ActionRequest.click(at: Point(x: 0, y: 600)).boundsError(for: area))
        XCTAssertNotNil(ActionRequest.click(at: Point(x: -1, y: 0)).boundsError(for: area))
        XCTAssertNotNil(ActionRequest.click(at: Point(x: 500, y: 300)).boundsError(for: area))
    }

    func testBoundsCheckDragValidatesBothPoints() {
        let area = CaptureArea(x: 0, y: 0, width: 100, height: 100)
        // from valid, to invalid
        XCTAssertNotNil(ActionRequest.drag(from: Point(x: 50, y: 50), to: Point(x: 150, y: 50)).boundsError(for: area))
        // from invalid, to valid
        XCTAssertNotNil(ActionRequest.drag(from: Point(x: -1, y: 50), to: Point(x: 50, y: 50)).boundsError(for: area))
        // both valid
        XCTAssertNil(ActionRequest.drag(from: Point(x: 10, y: 10), to: Point(x: 90, y: 90)).boundsError(for: area))
    }

    func testBoundsCheckScrollAtPosition() {
        let area = CaptureArea(x: 0, y: 0, width: 100, height: 100)
        XCTAssertNil(ActionRequest.scroll(delta: Delta(dx: 0, dy: -50), at: Point(x: 50, y: 50)).boundsError(for: area))
        XCTAssertNotNil(ActionRequest.scroll(delta: Delta(dx: 0, dy: -50), at: Point(x: 150, y: 50)).boundsError(for: area))
    }

    func testBoundsCheckTypeAndKeyAlwaysPass() {
        let area = CaptureArea(x: 0, y: 0, width: 100, height: 100)
        XCTAssertNil(ActionRequest.type(text: "hello").boundsError(for: area))
        XCTAssertNil(ActionRequest.key(key: "enter").boundsError(for: area))
    }

    // MARK: - File I/O

    func testActionFileWriteAndRead() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("action-test-\(UUID().uuidString)")
        let file = dir.appendingPathComponent("action.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let action = ActionRequest.click(at: Point(x: 10, y: 20))
        try ActionFile.write(action, to: file, createDirectory: dir)

        let read = try ActionFile.readAction(from: file)
        if case .click(let pt) = read {
            XCTAssertEqual(pt.x, 10)
        } else {
            XCTFail("Expected click")
        }
    }

    func testResultFileWriteAndRead() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("action-test-\(UUID().uuidString)")
        let file = dir.appendingPathComponent("result.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = ActionResult(success: true, message: "OK")
        try ActionFile.writeResult(result, to: file, createDirectory: dir)

        let read = try ActionFile.readResult(from: file)
        XCTAssertTrue(read.success)
        XCTAssertEqual(read.message, "OK")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ActionTests 2>&1`
Expected: Compilation error — `ActionRequest`, `ActionResult`, `Point`, `Delta`, `ActionFile` not found

- [ ] **Step 3: Implement Action.swift**

`Sources/ClaudeVisionShared/Action.swift`:
```swift
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

    // Custom Codable to match the flat JSON schema from the spec
    enum CodingKeys: String, CodingKey {
        case action, at, text, key, delta, from, to, timestamp
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
        }
    }

    /// Returns an error message if any coordinates are outside the area bounds, or nil if valid.
    public func boundsError(for area: CaptureArea) -> String? {
        func check(_ point: Point, label: String) -> String? {
            if point.x < 0 || point.x >= area.width || point.y < 0 || point.y >= area.height {
                return "Error: \(label)coordinates (\(Int(point.x)), \(Int(point.y))) are outside the selected area (\(Int(area.width))x\(Int(area.height)))"
            }
            return nil
        }

        switch self {
        case .click(let pt):
            return check(pt, label: "")
        case .scroll(_, let pt):
            return check(pt, label: "")
        case .drag(let from, let to):
            return check(from, label: "'from' ") ?? check(to, label: "'to' ")
        case .type, .key:
            return nil
        }
    }

    /// Convert relative coordinates to absolute screen coordinates.
    public func toAbsolute(area: CaptureArea) -> ActionRequest {
        func abs(_ pt: Point) -> Point {
            Point(x: area.x + pt.x, y: area.y + pt.y)
        }
        switch self {
        case .click(let pt): return .click(at: abs(pt))
        case .scroll(let delta, let pt): return .scroll(delta: delta, at: abs(pt))
        case .drag(let from, let to): return .drag(from: abs(from), to: abs(to))
        case .type, .key: return self
        }
    }
}

public struct ActionResult: Codable, Sendable {
    public let success: Bool
    public let message: String
    public init(success: Bool, message: String) {
        self.success = success
        self.message = message
    }
}

public enum ActionFile {
    public static func write(_ action: ActionRequest, to path: URL, createDirectory dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(action)
        try data.write(to: path, options: .atomic)
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
```

- [ ] **Step 4: Add action file paths to Config.swift**

Add to `Sources/ClaudeVisionShared/Config.swift`:
```swift
public static let actionFilePath = stateDirectory.appendingPathComponent("action.json")
public static let actionResultFilePath = stateDirectory.appendingPathComponent("action-result.json")
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ActionTests 2>&1`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeVisionShared/Action.swift Sources/ClaudeVisionShared/Config.swift Tests/ClaudeVisionTests/ActionTests.swift
git commit -m "feat: add action types, bounds validation, and file I/O"
```

---

### Task 2: Key Mapping (TDD)

**Files:**
- Create: `Sources/ClaudeVisionShared/KeyMapping.swift`
- Create: `Tests/ClaudeVisionTests/KeyMappingTests.swift`

- [ ] **Step 1: Write failing tests**

`Tests/ClaudeVisionTests/KeyMappingTests.swift`:
```swift
import XCTest
@testable import ClaudeVisionShared

final class KeyMappingTests: XCTestCase {

    func testParseSimpleKey() throws {
        let parsed = try KeyMapping.parse("enter")
        XCTAssertEqual(parsed.keyCode, 0x24) // kVK_Return
        XCTAssertTrue(parsed.modifiers.isEmpty)
    }

    func testParseTab() throws {
        let parsed = try KeyMapping.parse("tab")
        XCTAssertEqual(parsed.keyCode, 0x30) // kVK_Tab
    }

    func testParseEscape() throws {
        let parsed = try KeyMapping.parse("escape")
        XCTAssertEqual(parsed.keyCode, 0x35) // kVK_Escape
    }

    func testParseArrowKeys() throws {
        XCTAssertEqual(try KeyMapping.parse("up").keyCode, 0x7E)
        XCTAssertEqual(try KeyMapping.parse("down").keyCode, 0x7D)
        XCTAssertEqual(try KeyMapping.parse("left").keyCode, 0x7B)
        XCTAssertEqual(try KeyMapping.parse("right").keyCode, 0x7C)
    }

    func testParseSingleChar() throws {
        let parsed = try KeyMapping.parse("a")
        XCTAssertEqual(parsed.keyCode, 0x00) // kVK_ANSI_A
        XCTAssertTrue(parsed.modifiers.isEmpty)
    }

    func testParseWithModifiers() throws {
        let parsed = try KeyMapping.parse("cmd+a")
        XCTAssertEqual(parsed.keyCode, 0x00) // kVK_ANSI_A
        XCTAssertTrue(parsed.modifiers.contains(.maskCommand))
    }

    func testParseMultipleModifiers() throws {
        let parsed = try KeyMapping.parse("cmd+shift+z")
        XCTAssertEqual(parsed.keyCode, 0x06) // kVK_ANSI_Z
        XCTAssertTrue(parsed.modifiers.contains(.maskCommand))
        XCTAssertTrue(parsed.modifiers.contains(.maskShift))
    }

    func testParseAltModifier() throws {
        let parsed = try KeyMapping.parse("alt+tab")
        XCTAssertEqual(parsed.keyCode, 0x30) // kVK_Tab
        XCTAssertTrue(parsed.modifiers.contains(.maskAlternate))
    }

    func testParseCtrlModifier() throws {
        let parsed = try KeyMapping.parse("ctrl+c")
        XCTAssertEqual(parsed.keyCode, 0x08) // kVK_ANSI_C
        XCTAssertTrue(parsed.modifiers.contains(.maskControl))
    }

    func testParseUnknownKeyThrows() {
        XCTAssertThrowsError(try KeyMapping.parse("nonexistent"))
    }

    func testParseSpaceKey() throws {
        let parsed = try KeyMapping.parse("space")
        XCTAssertEqual(parsed.keyCode, 0x31) // kVK_Space
    }

    func testParseDeleteAndBackspace() throws {
        XCTAssertEqual(try KeyMapping.parse("delete").keyCode, 0x75)    // kVK_ForwardDelete
        XCTAssertEqual(try KeyMapping.parse("backspace").keyCode, 0x33) // kVK_Delete
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter KeyMappingTests 2>&1`
Expected: Compilation error — `KeyMapping` not found

- [ ] **Step 3: Implement KeyMapping.swift**

`Sources/ClaudeVisionShared/KeyMapping.swift`:
```swift
import CoreGraphics

public struct ParsedKey: Sendable {
    public let keyCode: CGKeyCode
    public let modifiers: CGEventFlags
}

public enum KeyMappingError: Error, CustomStringConvertible {
    case unknownKey(String)

    public var description: String {
        switch self {
        case .unknownKey(let key):
            return "Error: unknown key '\(key)'. Supported keys: enter, tab, escape, space, delete, backspace, up, down, left, right, home, end, and single characters (a-z, 0-9)."
        }
    }
}

public enum KeyMapping {
    // Named key → virtual key code
    private static let namedKeys: [String: CGKeyCode] = [
        "enter": 0x24, "return": 0x24,
        "tab": 0x30,
        "escape": 0x35, "esc": 0x35,
        "space": 0x31,
        "delete": 0x75,       // Forward delete
        "backspace": 0x33,    // Backward delete (kVK_Delete)
        "up": 0x7E, "down": 0x7D, "left": 0x7B, "right": 0x7C,
        "home": 0x73, "end": 0x77,
    ]

    // Single character → virtual key code (US keyboard layout)
    private static let charKeys: [Character: CGKeyCode] = [
        "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E,
        "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
        "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F,
        "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
        "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10,
        "z": 0x06,
        "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
        "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
    ]

    private static let modifierMap: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand,
        "shift": .maskShift,
        "alt": .maskAlternate, "option": .maskAlternate,
        "ctrl": .maskControl, "control": .maskControl,
    ]

    /// Parse a key string like "cmd+shift+a" into a keyCode and modifier flags.
    public static func parse(_ input: String) throws -> ParsedKey {
        let parts = input.lowercased().split(separator: "+").map(String.init)

        var modifiers: CGEventFlags = []
        var keyPart: String?

        for part in parts {
            if let mod = modifierMap[part] {
                modifiers.insert(mod)
            } else {
                keyPart = part
            }
        }

        guard let key = keyPart else {
            throw KeyMappingError.unknownKey(input)
        }

        // Check named keys first
        if let code = namedKeys[key] {
            return ParsedKey(keyCode: code, modifiers: modifiers)
        }

        // Check single character
        if key.count == 1, let char = key.first, let code = charKeys[char] {
            return ParsedKey(keyCode: code, modifiers: modifiers)
        }

        throw KeyMappingError.unknownKey(input)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter KeyMappingTests 2>&1`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeVisionShared/KeyMapping.swift Tests/ClaudeVisionTests/KeyMappingTests.swift
git commit -m "feat: add key name to virtual key code mapping"
```

---

### Task 3: CLI Control Subcommands

**Files:**
- Modify: `Sources/claude-vision/CLI.swift`

- [ ] **Step 1: Add Control subcommand group to CLI.swift**

Add `Control.self` to the subcommands list in `ClaudeVision`:
```swift
subcommands: [Start.self, Wait.self, Capture.self, Stop.self, Control.self]
```

Add a helper function used by all control subcommands (add before the `Control` struct):
```swift
/// Shared logic: read state, validate app running + area selected, return area.
func requireArea() throws -> CaptureArea {
    guard let state = try StateFile.read(from: Config.stateFilePath),
          StateFile.isProcessRunning(pid: state.pid) else {
        fputs("Claude Vision is not running. Use 'claude-vision start' first.\n", stderr)
        throw ExitCode.failure
    }
    guard let area = state.area else {
        fputs("No area selected. Use 'claude-vision start' to launch and select an area.\n", stderr)
        throw ExitCode.failure
    }
    return area
}

/// Send an action to the GUI and wait for the result. Handles bounds check, file write, polling.
func sendAction(_ action: ActionRequest, area: CaptureArea) throws {
    // Bounds check
    if let error = action.boundsError(for: area) {
        fputs("\(error)\n", stderr)
        throw ExitCode.failure
    }

    // Clean up any stale action files
    ActionFile.delete(at: Config.actionFilePath)
    ActionFile.delete(at: Config.actionResultFilePath)

    // Write action request
    try ActionFile.write(action, to: Config.actionFilePath, createDirectory: Config.stateDirectory)

    // Poll for result (5 second timeout)
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: Config.actionResultFilePath.path) {
            let result = try ActionFile.readResult(from: Config.actionResultFilePath)
            ActionFile.delete(at: Config.actionResultFilePath)
            if result.success {
                print(result.message)
            } else {
                fputs("\(result.message)\n", stderr)
                throw ExitCode.failure
            }
            return
        }
        Thread.sleep(forTimeInterval: 0.05)
    }

    fputs("Error: action timed out — GUI may not be responding\n", stderr)
    throw ExitCode.failure
}
```

- [ ] **Step 2: Add the Control command group and subcommands**

```swift
struct Control: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Control the selected area",
        subcommands: [Click.self, TypeText.self, Key.self, Scroll.self, Drag.self]
    )
}

extension Control {
    struct Click: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Left-click at a position")

        @Option(name: .long, help: "Position as X,Y relative to area top-left")
        var at: String

        func run() throws {
            let area = try requireArea()
            let point = try parsePoint(at)
            try sendAction(.click(at: point), area: area)
        }
    }

    struct TypeText: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "type",
            abstract: "Type text at current cursor position"
        )

        @Option(name: .long, help: "Text to type")
        var text: String

        func run() throws {
            let area = try requireArea()
            try sendAction(.type(text: text), area: area)
        }
    }

    struct Key: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Press a key or key combination")

        @Option(name: .long, help: "Key to press (e.g. enter, tab, cmd+a, shift+tab)")
        var key: String

        func run() throws {
            // Validate key name early (before sending to GUI)
            do {
                _ = try KeyMapping.parse(key)
            } catch {
                fputs("\(error)\n", stderr)
                throw ExitCode.failure
            }

            let area = try requireArea()
            try sendAction(.key(key: key), area: area)
        }
    }

    struct Scroll: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Scroll by pixel delta")

        @Option(name: .long, help: "Scroll delta as DX,DY (negative Y = scroll down)")
        var delta: String

        @Option(name: .long, help: "Position as X,Y (default: center of area)")
        var at: String?

        func run() throws {
            let area = try requireArea()
            let d = try parseDelta(delta)
            let point: Point
            if let atStr = at {
                point = try parsePoint(atStr)
            } else {
                point = Point(x: area.width / 2, y: area.height / 2)
            }
            try sendAction(.scroll(delta: d, at: point), area: area)
        }
    }

    struct Drag: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Click and drag between two points")

        @Option(name: .long, help: "Start position as X,Y")
        var from: String

        @Option(name: .long, help: "End position as X,Y")
        var to: String

        func run() throws {
            let area = try requireArea()
            let fromPt = try parsePoint(from)
            let toPt = try parsePoint(to)
            try sendAction(.drag(from: fromPt, to: toPt), area: area)
        }
    }
}

// MARK: - Argument Parsing Helpers

func parsePoint(_ str: String) throws -> Point {
    let parts = str.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == 2 else {
        throw ValidationError("Invalid position '\(str)'. Expected format: X,Y (e.g. 150,300)")
    }
    return Point(x: parts[0], y: parts[1])
}

func parseDelta(_ str: String) throws -> Delta {
    let parts = str.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == 2 else {
        throw ValidationError("Invalid delta '\(str)'. Expected format: DX,DY (e.g. 0,-100)")
    }
    return Delta(dx: parts[0], dy: parts[1])
}
```

- [ ] **Step 3: Build and verify**

Run: `swift build 2>&1`
Expected: Compiles successfully

- [ ] **Step 4: Verify CLI help**

Run: `.build/debug/claude-vision control --help`
Expected: Shows click, type, key, scroll, drag subcommands

Run: `.build/debug/claude-vision control click --help`
Expected: Shows --at option

- [ ] **Step 5: Commit**

```bash
git add Sources/claude-vision/CLI.swift
git commit -m "feat: add control subcommand group with click, type, key, scroll, drag"
```

---

### Task 4: Action Watcher + CGEvent Execution (GUI)

**Files:**
- Create: `Sources/claude-vision-app/ActionWatcher.swift`
- Modify: `Sources/claude-vision-app/AppDelegate.swift`

- [ ] **Step 1: Create ActionWatcher**

`Sources/claude-vision-app/ActionWatcher.swift`:
```swift
import AppKit
import ClaudeVisionShared
import CoreGraphics

@MainActor
class ActionWatcher {
    private var timer: Timer?
    private var onFeedback: ((ActionRequest, CaptureArea) -> Void)?

    func start(onFeedback: @escaping (ActionRequest, CaptureArea) -> Void) {
        self.onFeedback = onFeedback
        // Poll for action.json every 100ms
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForAction()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkForAction() {
        let actionPath = Config.actionFilePath
        guard FileManager.default.fileExists(atPath: actionPath.path) else { return }

        do {
            let action = try ActionFile.readAction(from: actionPath)

            // Get current area from state
            guard let state = try StateFile.read(from: Config.stateFilePath),
                  let area = state.area else {
                let result = ActionResult(success: false, message: "No area selected")
                try? ActionFile.writeResult(result, to: Config.actionResultFilePath, createDirectory: Config.stateDirectory)
                ActionFile.delete(at: actionPath)
                return
            }

            // Check accessibility permission
            guard AXIsProcessTrusted() else {
                let result = ActionResult(success: false, message: "Error: Accessibility permission required. Enable it in System Settings > Privacy & Security > Accessibility.")
                try? ActionFile.writeResult(result, to: Config.actionResultFilePath, createDirectory: Config.stateDirectory)
                ActionFile.delete(at: actionPath)
                return
            }

            // Convert to absolute coordinates
            let absoluteAction = action.toAbsolute(area: area)

            // Execute the action
            let message = try executeAction(absoluteAction, original: action)

            // Show visual feedback
            onFeedback?(action, area)

            // Write success result
            let result = ActionResult(success: true, message: message)
            try ActionFile.writeResult(result, to: Config.actionResultFilePath, createDirectory: Config.stateDirectory)
        } catch {
            let result = ActionResult(success: false, message: "Error: \(error)")
            try? ActionFile.writeResult(result, to: Config.actionResultFilePath, createDirectory: Config.stateDirectory)
        }

        ActionFile.delete(at: actionPath)
    }

    private func executeAction(_ action: ActionRequest, original: ActionRequest) throws -> String {
        let source = CGEventSource(stateID: .hidSystemState)

        switch action {
        case .click(let pt):
            let point = CGPoint(x: pt.x, y: pt.y)
            let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
            let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
            mouseDown?.post(tap: .cghidEventTap)
            mouseUp?.post(tap: .cghidEventTap)
            if case .click(let orig) = original {
                return "Clicked at (\(Int(orig.x)), \(Int(orig.y)))"
            }
            return "Clicked"

        case .type(let text):
            for char in text {
                let str = String(char) as CFString
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                var unichar = UniChar(char.asciiValue ?? 0)
                if char.asciiValue == nil {
                    // Handle unicode characters
                    let utf16 = Array(String(char).utf16)
                    unichar = utf16.first ?? 0
                }
                keyDown?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                keyUp?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unichar)
                keyDown?.post(tap: .cghidEventTap)
                keyUp?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.01)
            }
            return "Typed \"\(text)\""

        case .key(let keyStr):
            let parsed = try KeyMapping.parse(keyStr)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: parsed.keyCode, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: parsed.keyCode, keyDown: false)
            keyDown?.flags = parsed.modifiers
            keyUp?.flags = parsed.modifiers
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            return "Pressed \(keyStr)"

        case .scroll(let delta, let pt):
            let point = CGPoint(x: pt.x, y: pt.y)
            // Move mouse to scroll position first
            let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
            move?.post(tap: .cghidEventTap)

            let scrollEvent = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: Int32(delta.dy), wheel2: Int32(delta.dx))
            scrollEvent?.post(tap: .cghidEventTap)

            if case .scroll(_, let origPt) = original {
                return "Scrolled by (\(Int(delta.dx)), \(Int(delta.dy))) at (\(Int(origPt.x)), \(Int(origPt.y)))"
            }
            return "Scrolled"

        case .drag(let from, let to):
            let startPoint = CGPoint(x: from.x, y: from.y)
            let endPoint = CGPoint(x: to.x, y: to.y)

            // Mouse down at start
            let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: startPoint, mouseButton: .left)
            mouseDown?.post(tap: .cghidEventTap)

            // Interpolate drag events (10px steps)
            let dx = endPoint.x - startPoint.x
            let dy = endPoint.y - startPoint.y
            let distance = sqrt(dx * dx + dy * dy)
            let steps = max(Int(distance / 10), 1)

            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let current = CGPoint(x: startPoint.x + dx * t, y: startPoint.y + dy * t)
                let dragEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: current, mouseButton: .left)
                dragEvent?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.01)
            }

            // Mouse up at end
            let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: endPoint, mouseButton: .left)
            mouseUp?.post(tap: .cghidEventTap)

            if case .drag(let origFrom, let origTo) = original {
                return "Dragged from (\(Int(origFrom.x)), \(Int(origFrom.y))) to (\(Int(origTo.x)), \(Int(origTo.y)))"
            }
            return "Dragged"
        }
    }
}
```

- [ ] **Step 2: Wire up ActionWatcher in AppDelegate**

Add a property to `AppDelegate`:
```swift
var actionWatcher: ActionWatcher?
```

At the end of `applicationDidFinishLaunching`, add:
```swift
// Start watching for action requests
actionWatcher = ActionWatcher()
actionWatcher?.start { [weak self] action, area in
    self?.showActionFeedback(action: action, area: area)
}
```

Add a placeholder method:
```swift
func showActionFeedback(action: ActionRequest, area: CaptureArea) {
    // TODO: Visual feedback (Task 5)
}
```

In `applicationWillTerminate`, add:
```swift
actionWatcher?.stop()
ActionFile.delete(at: Config.actionFilePath)
ActionFile.delete(at: Config.actionResultFilePath)
```

- [ ] **Step 3: Build and verify**

Run: `swift build 2>&1`
Expected: Compiles successfully

- [ ] **Step 4: Commit**

```bash
git add Sources/claude-vision-app/ActionWatcher.swift Sources/claude-vision-app/AppDelegate.swift
git commit -m "feat: add action watcher with CGEvent execution"
```

---

### Task 5: Visual Feedback Window (GUI)

**Files:**
- Create: `Sources/claude-vision-app/ActionFeedbackWindow.swift`
- Modify: `Sources/claude-vision-app/AppDelegate.swift`

- [ ] **Step 1: Create ActionFeedbackWindow**

`Sources/claude-vision-app/ActionFeedbackWindow.swift`:
```swift
import AppKit
import ClaudeVisionShared

class ActionFeedbackWindow: NSWindow {
    private var feedbackView: FeedbackView!

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        feedbackView = FeedbackView(frame: screen.frame)
        contentView = feedbackView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Show a ripple at a screen position (absolute Quartz coordinates).
    func showRipple(at screenPoint: CGPoint) {
        // Convert from Quartz (top-left) to AppKit (bottom-left)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let appKitY = screen.frame.height - screenPoint.y
        let viewPoint = NSPoint(x: screenPoint.x - frame.origin.x, y: appKitY - frame.origin.y)

        makeKeyAndOrderFront(nil)
        feedbackView.animateRipple(at: viewPoint)

        // Auto-dismiss after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.orderOut(nil)
        }
    }
}

class FeedbackView: NSView {
    private var rippleCenter: NSPoint?
    private var rippleProgress: CGFloat = 0
    private var displayLink: CVDisplayLink?
    private var animationTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func animateRipple(at point: NSPoint) {
        rippleCenter = point
        rippleProgress = 0

        // Simple timer-based animation (60fps for 250ms)
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.rippleProgress += 1.0 / 15.0 // 15 frames ≈ 250ms
            if self.rippleProgress >= 1.0 {
                timer.invalidate()
                self.rippleCenter = nil
            }
            self.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let center = rippleCenter else { return }

        let startSize: CGFloat = 20
        let endSize: CGFloat = 30
        let size = startSize + (endSize - startSize) * rippleProgress
        let alpha = 1.0 - rippleProgress

        let blue = NSColor(red: 0, green: 0.478, blue: 1, alpha: alpha * 0.6)
        let borderBlue = NSColor(red: 0, green: 0.478, blue: 1, alpha: alpha)

        let rect = NSRect(
            x: center.x - size / 2,
            y: center.y - size / 2,
            width: size,
            height: size
        )

        let path = NSBezierPath(ovalIn: rect)
        blue.setFill()
        path.fill()
        borderBlue.setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
```

- [ ] **Step 2: Wire up visual feedback in AppDelegate**

Replace the `showActionFeedback` placeholder method:
```swift
var feedbackWindow: ActionFeedbackWindow?

func showActionFeedback(action: ActionRequest, area: CaptureArea) {
    if feedbackWindow == nil {
        feedbackWindow = ActionFeedbackWindow()
    }

    // Determine the screen point for feedback
    let screenPoint: CGPoint
    switch action {
    case .click(let pt):
        screenPoint = CGPoint(x: area.x + pt.x, y: area.y + pt.y)
    case .scroll(_, let pt):
        screenPoint = CGPoint(x: area.x + pt.x, y: area.y + pt.y)
    case .drag(let from, _):
        screenPoint = CGPoint(x: area.x + from.x, y: area.y + from.y)
    case .type, .key:
        screenPoint = CGPoint(x: area.x + area.width / 2, y: area.y + area.height / 2)
    }

    feedbackWindow?.showRipple(at: screenPoint)
}
```

- [ ] **Step 3: Build and verify**

Run: `swift build 2>&1`
Expected: Compiles successfully

- [ ] **Step 4: Commit**

```bash
git add Sources/claude-vision-app/ActionFeedbackWindow.swift Sources/claude-vision-app/AppDelegate.swift
git commit -m "feat: add visual ripple feedback for actions"
```

---

### Task 6: README Update — Control Instructions for Claude

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README**

Add the following sections. In the **CLI Reference** section, after `claude-vision stop`, add the control commands reference. In the **Instructions for Claude** section, add control workflows.

Add to CLI Reference (after `claude-vision stop`):

```markdown
### `claude-vision control click --at X,Y`

Left-clicks at a position relative to the selected area's top-left corner (0,0).

```
$ claude-vision control click --at 150,300
Clicked at (150, 300)
```

### `claude-vision control type --text TEXT`

Types text at the current cursor position.

```
$ claude-vision control type --text "hello world"
Typed "hello world"
```

### `claude-vision control key --key KEY`

Presses a key or key combination. Supports: `enter`, `tab`, `escape`, `space`, `delete`, `backspace`, `up`, `down`, `left`, `right`, `home`, `end`. Modifiers: `cmd+`, `shift+`, `alt+`, `ctrl+`.

```
$ claude-vision control key --key enter
Pressed enter

$ claude-vision control key --key "cmd+a"
Pressed cmd+a
```

### `claude-vision control scroll --delta DX,DY [--at X,Y]`

Scrolls by pixel delta. Negative Y = scroll down, positive Y = scroll up. Position defaults to center of area.

```
$ claude-vision control scroll --delta 0,-100
Scrolled by (0, -100) at (200, 300)
```

### `claude-vision control drag --from X,Y --to X,Y`

Click-and-drag between two points. Useful for mobile simulator swipe gestures.

```
$ claude-vision control drag --from 150,400 --to 150,100
Dragged from (150, 400) to (150, 100)
```
```

Add to Instructions for Claude section — new workflow:

```markdown
### Workflow: Interactive UI Testing

Use capture + control for a full interaction loop:

```bash
# 1. See the current state
claude-vision capture
# Read the screenshot to understand the UI layout

# 2. Interact with an element (e.g., click a button at coordinates you identified)
claude-vision control click --at 200,150

# 3. Wait for UI response
sleep 1

# 4. Capture the result to verify
claude-vision capture
# Read the new screenshot to check what happened
```

### Workflow: Filling a Form

```bash
# Capture to see the form
claude-vision capture

# Click on the first input field
claude-vision control click --at 200,100

# Type into it
claude-vision control type --text "John Doe"

# Tab to next field
claude-vision control key --key tab

# Type into next field
claude-vision control type --text "john@example.com"

# Submit the form
claude-vision control key --key enter

# Capture to verify
sleep 1
claude-vision capture
```

### Workflow: Scrolling to Find Content

```bash
# Capture current view
claude-vision capture

# If the content you need isn't visible, scroll down
claude-vision control scroll --delta 0,-300

# Capture again to see new content
sleep 0.5
claude-vision capture
```

### Workflow: Mobile Simulator Swipe

```bash
# Swipe up in a mobile simulator (drag from bottom to top)
claude-vision control drag --from 200,500 --to 200,100

# Wait and capture
sleep 1
claude-vision capture
```

### Control Coordinates

- All positions are relative to the **top-left corner** of the selected area
- `(0, 0)` = top-left corner of the area
- `(area_width-1, area_height-1)` = bottom-right corner
- To find where to click, capture a screenshot first and identify element positions visually
- **All actions are bounds-checked** — you cannot accidentally interact outside the selected area

### Control Error Handling

| Error | What to do |
|-------|-----------|
| `coordinates are outside the selected area` | Check your X,Y values against the area dimensions |
| `Accessibility permission required` | Ask user to enable Accessibility for Claude Vision in System Settings > Privacy & Security > Accessibility |
| `action timed out` | The GUI may not be responding — ask user to check if Claude Vision is still running |
| `unknown key` | Check supported key names in `claude-vision control key --help` |
```

Add to the **How It Works** section, add a bullet:
```markdown
- **Input Controls**: Actions (click, scroll, type, etc.) are sent via JSON files to the GUI, which executes them using the macOS CGEvent API. A visual ripple appears at each action point. All coordinates are bounds-checked to stay within the selected area.
```

Add to the **Install** section:
```markdown
Requires macOS 13+, Screen Recording permission, and Accessibility permission (for input controls).
```

Update the **Quick Start** to show a control example:
```bash
claude-vision start          # Shows floating toolbar
# Click "Select Area" on the toolbar, drag to select a screen region
claude-vision wait           # Blocks until area is selected
claude-vision capture        # Screenshot the area
claude-vision control click --at 100,50   # Click within the area
claude-vision stop           # Quit
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add input control instructions for Claude"
```

---

### Task 7: Integration Test + Reinstall

**Files:**
- No new files

- [ ] **Step 1: Run all tests**

Run: `swift test 2>&1`
Expected: All tests pass

- [ ] **Step 2: Build release**

Run: `swift build -c release 2>&1`
Expected: Build succeeds

- [ ] **Step 3: Reinstall the .app**

Run: `./scripts/install.sh`
Expected: Rebuilds and installs to /Applications

- [ ] **Step 4: Manual integration test**

```bash
# Start the app
claude-vision start
# Select an area (click Select Area on toolbar, drag over a region)
claude-vision wait

# Test click
claude-vision control click --at 50,50
# Should print: Clicked at (50, 50)

# Test type
claude-vision control type --text "hello"
# Should print: Typed "hello"

# Test key
claude-vision control key --key enter
# Should print: Pressed enter

# Test scroll
claude-vision control scroll --delta 0,-100
# Should print: Scrolled by (0, -100) at (...)

# Test bounds checking
claude-vision control click --at 99999,0
# Should print error about coordinates outside area

# Test capture still works
claude-vision capture
# Should print path to screenshot

# Stop
claude-vision stop
```

- [ ] **Step 5: Verify error cases**

```bash
# Control without app running
claude-vision control click --at 50,50
# Should print: Claude Vision is not running

# Invalid key
claude-vision control key --key nonexistent
# Should print: Error: unknown key 'nonexistent'
```

- [ ] **Step 6: Tag release**

```bash
git tag v0.2.0
```
