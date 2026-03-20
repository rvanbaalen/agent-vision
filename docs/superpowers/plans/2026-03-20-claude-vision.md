# Claude Vision Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS utility that lets users mark a screen region via a floating toolbar and exposes a CLI for Claude Code to capture screenshots of that region.

**Architecture:** Two Swift executables (CLI + GUI app) sharing state via a JSON file at `~/.claude-vision/state.json`. The CLI is the primary entry point — it launches the GUI, polls for area selection, captures screenshots, and stops the app. The GUI is a floating toolbar with area selection and border overlay.

**Tech Stack:** Swift 6, AppKit, CGWindowListCreateImage, Swift Package Manager, swift-argument-parser

---

## File Structure

```
claude-vision/
├── Package.swift                          # SPM manifest: 2 executables + 1 library
├── Sources/
│   ├── claude-vision/                     # CLI executable target
│   │   └── CLI.swift                      # @main, ArgumentParser commands
│   ├── claude-vision-app/                 # GUI executable target
│   │   ├── main.swift                     # NSApplication setup + run loop
│   │   ├── AppDelegate.swift              # App lifecycle, state file cleanup
│   │   ├── ToolbarWindow.swift            # Floating toolbar panel
│   │   ├── SelectionOverlay.swift         # Full-screen drag-to-select overlay
│   │   └── BorderWindow.swift             # Persistent dashed border around area
│   └── ClaudeVisionShared/                # Shared library target
│       ├── State.swift                    # StateFile: Codable types, read/write/delete
│       ├── Config.swift                   # Paths (~/.claude-vision/), constants
│       └── Capture.swift                  # Screenshot capture using CGWindowListCreateImage
├── Tests/
│   └── ClaudeVisionTests/
│       ├── StateTests.swift               # State file read/write/delete/stale PID
│       ├── ConfigTests.swift              # Path construction
│       └── CaptureTests.swift             # Capture to file (integration)
└── .gitignore
```

**Key decisions:**
- CLI target named `claude-vision` so the binary is `claude-vision` out of the box
- GUI target named `claude-vision-app` — launched as a subprocess by the CLI
- Shared library keeps State/Config/Capture logic testable and DRY
- Capture logic lives in Shared (not GUI) because the CLI process does the capturing

---

### Task 1: Project Scaffold + Package.swift

**Files:**
- Create: `Package.swift`
- Create: `Sources/claude-vision/CLI.swift`
- Create: `Sources/claude-vision-app/main.swift`
- Create: `Sources/ClaudeVisionShared/Config.swift`

- [ ] **Step 1: Create Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "claude-vision",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "claude-vision",
            dependencies: [
                "ClaudeVisionShared",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "claude-vision-app",
            dependencies: ["ClaudeVisionShared"]
        ),
        .target(
            name: "ClaudeVisionShared"
        ),
        .testTarget(
            name: "ClaudeVisionTests",
            dependencies: ["ClaudeVisionShared"]
        ),
    ]
)
```

- [ ] **Step 2: Create minimal source files so it compiles**

`Sources/ClaudeVisionShared/Config.swift`:
```swift
import Foundation

public enum Config {
    public static let stateDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude-vision")
    public static let stateFilePath = stateDirectory.appendingPathComponent("state.json")
}
```

`Sources/claude-vision/CLI.swift`:
```swift
import ArgumentParser

@main
struct ClaudeVision: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "claude-vision",
        abstract: "Screen region capture tool for Claude Code",
        subcommands: [Start.self, Wait.self, Capture.self, Stop.self]
    )
}

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Launch the toolbar GUI")
    func run() throws { print("TODO: start") }
}

struct Wait: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Wait for area selection")
    func run() throws { print("TODO: wait") }
}

struct Capture: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Capture the selected area")
    func run() throws { print("TODO: capture") }
}

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop the GUI")
    func run() throws { print("TODO: stop") }
}
```

`Sources/claude-vision-app/main.swift`:
```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// AppDelegate will be added in Task 5
app.run()
```

- [ ] **Step 3: Build and verify**

Run: `swift build 2>&1`
Expected: Build succeeds, produces `.build/debug/claude-vision` and `.build/debug/claude-vision-app`

- [ ] **Step 4: Verify CLI runs**

Run: `.build/debug/claude-vision --help`
Expected: Shows help with start/wait/capture/stop subcommands

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/ .gitignore
git commit -m "feat: scaffold SPM project with CLI and GUI targets"
```

---

### Task 2: State File Management (TDD)

**Files:**
- Create: `Sources/ClaudeVisionShared/State.swift`
- Create: `Tests/ClaudeVisionTests/StateTests.swift`

- [ ] **Step 1: Write failing tests for State types and file operations**

`Tests/ClaudeVisionTests/StateTests.swift`:
```swift
import XCTest
@testable import ClaudeVisionShared

final class StateTests: XCTestCase {
    var testDir: URL!
    var testFile: URL!

    override func setUp() {
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-vision-test-\(UUID().uuidString)")
        testFile = testDir.appendingPathComponent("state.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testDir)
    }

    func testAreaEncodesAndDecodes() throws {
        let area = CaptureArea(x: 100, y: 200, width: 800, height: 600)
        let data = try JSONEncoder().encode(area)
        let decoded = try JSONDecoder().decode(CaptureArea.self, from: data)
        XCTAssertEqual(decoded.x, 100)
        XCTAssertEqual(decoded.y, 200)
        XCTAssertEqual(decoded.width, 800)
        XCTAssertEqual(decoded.height, 600)
    }

    func testWriteAndReadState() throws {
        let state = AppState(pid: 12345, area: CaptureArea(x: 10, y: 20, width: 300, height: 200))
        try StateFile.write(state, to: testFile, createDirectory: testDir)
        let read = try StateFile.read(from: testFile)
        XCTAssertEqual(read.pid, 12345)
        XCTAssertEqual(read.area?.width, 300)
    }

    func testWriteStatePidOnly() throws {
        let state = AppState(pid: 99, area: nil)
        try StateFile.write(state, to: testFile, createDirectory: testDir)
        let read = try StateFile.read(from: testFile)
        XCTAssertEqual(read.pid, 99)
        XCTAssertNil(read.area)
    }

    func testReadNonexistentReturnsNil() {
        let result = try? StateFile.read(from: testFile)
        XCTAssertNil(result)
    }

    func testDeleteRemovesFile() throws {
        let state = AppState(pid: 1, area: nil)
        try StateFile.write(state, to: testFile, createDirectory: testDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFile.path))
        StateFile.delete(at: testFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path))
    }

    func testIsProcessRunningReturnsTrueForSelf() {
        // Our own PID should be alive
        let pid = ProcessInfo.processInfo.processIdentifier
        XCTAssertTrue(StateFile.isProcessRunning(pid: pid))
    }

    func testIsProcessRunningReturnsFalseForBogus() {
        // PID 99999 is almost certainly not running
        XCTAssertFalse(StateFile.isProcessRunning(pid: 99999))
    }

    func testStateFilePermissions() throws {
        let state = AppState(pid: 1, area: nil)
        try StateFile.write(state, to: testFile, createDirectory: testDir)
        let attributes = try FileManager.default.attributesOfItem(atPath: testFile.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter StateTests 2>&1`
Expected: Compilation error — `CaptureArea`, `AppState`, `StateFile` not found

- [ ] **Step 3: Implement State.swift**

`Sources/ClaudeVisionShared/State.swift`:
```swift
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

    public static func read(from path: URL) throws -> AppState? {
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter StateTests 2>&1`
Expected: All 8 tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeVisionShared/State.swift Tests/
git commit -m "feat: add state file management with TDD"
```

---

### Task 3: Screen Capture Logic (TDD)

**Files:**
- Create: `Sources/ClaudeVisionShared/Capture.swift`
- Create: `Tests/ClaudeVisionTests/CaptureTests.swift`

- [ ] **Step 1: Write failing test for screenshot capture**

`Tests/ClaudeVisionTests/CaptureTests.swift`:
```swift
import XCTest
@testable import ClaudeVisionShared

final class CaptureTests: XCTestCase {
    func testCaptureAreaToFile() throws {
        let area = CaptureArea(x: 0, y: 0, width: 100, height: 100)
        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-capture-\(UUID().uuidString).png")

        defer { try? FileManager.default.removeItem(at: outputPath) }

        try ScreenCapture.capture(area: area, to: outputPath)

        // Verify the file exists and is a valid PNG
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath.path))
        let data = try Data(contentsOf: outputPath)
        XCTAssertGreaterThan(data.count, 0)
        // PNG magic bytes: 0x89 0x50 0x4E 0x47
        XCTAssertEqual(data[0], 0x89)
        XCTAssertEqual(data[1], 0x50)
        XCTAssertEqual(data[2], 0x4E)
        XCTAssertEqual(data[3], 0x47)
    }

    func testCaptureToDefaultTempPath() throws {
        let area = CaptureArea(x: 0, y: 0, width: 50, height: 50)
        let path = try ScreenCapture.captureToTemp(area: area)

        defer { try? FileManager.default.removeItem(at: URL(fileURLWithPath: path)) }

        XCTAssertTrue(path.hasSuffix(".png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CaptureTests 2>&1`
Expected: Compilation error — `ScreenCapture` not found

- [ ] **Step 3: Implement Capture.swift**

`Sources/ClaudeVisionShared/Capture.swift`:
```swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum CaptureError: Error, CustomStringConvertible {
    case captureFailedNoImage
    case cannotCreateDestination(String)
    case writeFailed(String)

    public var description: String {
        switch self {
        case .captureFailedNoImage:
            return "Screen capture failed — no image returned. Check Screen Recording permission."
        case .cannotCreateDestination(let path):
            return "Cannot create image file at \(path)"
        case .writeFailed(let path):
            return "Failed to write image to \(path)"
        }
    }
}

public enum ScreenCapture {
    public static func capture(area: CaptureArea, to outputURL: URL) throws {
        let rect = CGRect(x: area.x, y: area.y, width: area.width, height: area.height)

        guard let image = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) else {
            throw CaptureError.captureFailedNoImage
        }

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureError.cannotCreateDestination(outputURL.path)
        }

        CGImageDestinationAddImage(destination, image, nil)

        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.writeFailed(outputURL.path)
        }
    }

    public static func captureToTemp(area: CaptureArea) throws -> String {
        let filename = "claude-vision-capture-\(Int(Date().timeIntervalSince1970)).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try capture(area: area, to: url)
        return url.path
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CaptureTests 2>&1`
Expected: Both tests pass (requires Screen Recording permission — CI may need special handling, but local dev should be fine)

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeVisionShared/Capture.swift Tests/ClaudeVisionTests/CaptureTests.swift
git commit -m "feat: add screen capture logic with TDD"
```

---

### Task 4: CLI Commands — start, stop, wait, capture

**Files:**
- Modify: `Sources/claude-vision/CLI.swift`

- [ ] **Step 1: Implement the Start command**

Replace the `Start` struct in `CLI.swift`:
```swift
struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Launch the toolbar GUI")

    func run() throws {
        // Check if already running
        if let state = try StateFile.read(from: Config.stateFilePath),
           StateFile.isProcessRunning(pid: state.pid) {
            print("Claude Vision is already running (PID \(state.pid))")
            return
        }

        // Clean up stale state
        StateFile.delete(at: Config.stateFilePath)

        // Find the app binary next to this CLI binary
        let cliURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardized
        let appURL = cliURL.deletingLastPathComponent().appendingPathComponent("claude-vision-app")

        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw ValidationError("Cannot find claude-vision-app at \(appURL.path). Build it first with 'swift build'.")
        }

        let process = Process()
        process.executableURL = appURL
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        print("Claude Vision started. Use the toolbar to select an area.")
    }
}
```

- [ ] **Step 2: Implement the Stop command**

Replace the `Stop` struct:
```swift
struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop the GUI")

    func run() throws {
        guard let state = try StateFile.read(from: Config.stateFilePath) else {
            print("Claude Vision is not running.")
            return
        }

        if StateFile.isProcessRunning(pid: state.pid) {
            kill(state.pid, SIGTERM)
        }

        StateFile.delete(at: Config.stateFilePath)
        print("Claude Vision stopped.")
    }
}
```

- [ ] **Step 3: Implement the Wait command**

Replace the `Wait` struct:
```swift
struct Wait: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Wait for area selection")

    @Option(name: .long, help: "Timeout in seconds (default: 60)")
    var timeout: Int = 60

    func run() throws {
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))

        while Date() < deadline {
            guard let state = try StateFile.read(from: Config.stateFilePath),
                  StateFile.isProcessRunning(pid: state.pid) else {
                fputs("Claude Vision is not running. Use 'claude-vision start' first.\n", stderr)
                throw ExitCode.failure
            }

            if let area = state.area {
                print("Area selected: \(Int(area.width))x\(Int(area.height)) at (\(Int(area.x)), \(Int(area.y)))")
                return
            }

            Thread.sleep(forTimeInterval: 0.5)
        }

        fputs("No area selected within \(timeout)s\n", stderr)
        throw ExitCode.failure
    }
}
```

- [ ] **Step 4: Implement the Capture command**

Replace the `Capture` struct:
```swift
struct Capture: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Capture the selected area")

    @Option(name: .long, help: "Output file path (default: temp file)")
    var output: String?

    func run() throws {
        guard let state = try StateFile.read(from: Config.stateFilePath),
              StateFile.isProcessRunning(pid: state.pid) else {
            fputs("Claude Vision is not running. Use 'claude-vision start' first.\n", stderr)
            throw ExitCode.failure
        }

        guard let area = state.area else {
            fputs("No area selected. Use 'claude-vision start' to launch and select an area.\n", stderr)
            throw ExitCode.failure
        }

        if let outputPath = output {
            try ScreenCapture.capture(area: area, to: URL(fileURLWithPath: outputPath))
            print(outputPath)
        } else {
            let path = try ScreenCapture.captureToTemp(area: area)
            print(path)
        }
    }
}
```

- [ ] **Step 5: Add imports at the top of CLI.swift**

Make sure `CLI.swift` has:
```swift
import ArgumentParser
import ClaudeVisionShared
import Foundation
```

- [ ] **Step 6: Build and verify**

Run: `swift build 2>&1`
Expected: Compiles successfully

- [ ] **Step 7: Test CLI help and subcommands**

Run: `.build/debug/claude-vision --help && .build/debug/claude-vision start --help && .build/debug/claude-vision capture --help`
Expected: Shows help for each command with correct options

- [ ] **Step 8: Commit**

```bash
git add Sources/claude-vision/CLI.swift
git commit -m "feat: implement CLI commands — start, stop, wait, capture"
```

---

### Task 5: GUI — AppDelegate + Toolbar Window

**Files:**
- Create: `Sources/claude-vision-app/AppDelegate.swift`
- Create: `Sources/claude-vision-app/ToolbarWindow.swift`
- Modify: `Sources/claude-vision-app/main.swift`

- [ ] **Step 1: Create AppDelegate**

`Sources/claude-vision-app/AppDelegate.swift`:
```swift
import AppKit
import ClaudeVisionShared

class AppDelegate: NSObject, NSApplicationDelegate {
    var toolbarWindow: ToolbarWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Write PID to state file
        let state = AppState(pid: ProcessInfo.processInfo.processIdentifier, area: nil)
        do {
            try StateFile.write(state, to: Config.stateFilePath, createDirectory: Config.stateDirectory)
        } catch {
            NSLog("Failed to write state file: \(error)")
            NSApp.terminate(nil)
            return
        }

        // Set up signal handler for cleanup
        signal(SIGTERM) { _ in
            StateFile.delete(at: Config.stateFilePath)
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }

        // Create and show toolbar
        toolbarWindow = ToolbarWindow()
        toolbarWindow.showToolbar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        StateFile.delete(at: Config.stateFilePath)
    }
}
```

- [ ] **Step 2: Create ToolbarWindow**

`Sources/claude-vision-app/ToolbarWindow.swift`:
```swift
import AppKit
import ClaudeVisionShared

class ToolbarWindow: NSPanel {
    init() {
        let toolbarWidth: CGFloat = 180
        let toolbarHeight: CGFloat = 60

        // Position at bottom center of main screen
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - toolbarWidth / 2
        let y = screenFrame.minY + 20

        super.init(
            contentRect: NSRect(x: x, y: y, width: toolbarWidth, height: toolbarHeight),
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear

        // Visual effect background
        let visualEffect = NSVisualEffectView(frame: bounds)
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 14

        // Close button
        let closeButton = NSButton(frame: .zero)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .circular
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.imageScaling = .scaleProportionallyUpOrDown
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.contentTintColor = .secondaryLabelColor

        // Select Area button
        let selectButton = NSButton(frame: .zero)
        selectButton.translatesAutoresizingMaskIntoConstraints = false
        selectButton.bezelStyle = .regularSquare
        selectButton.isBordered = false
        selectButton.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "Select Area")
        selectButton.imagePosition = .imageAbove
        selectButton.imageScaling = .scaleProportionallyUpOrDown
        selectButton.title = "Select Area"
        selectButton.font = .systemFont(ofSize: 10)
        selectButton.contentTintColor = .labelColor
        selectButton.target = self
        selectButton.action = #selector(selectAreaTapped)

        visualEffect.addSubview(closeButton)
        visualEffect.addSubview(selectButton)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 12),
            closeButton.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),

            selectButton.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor, constant: 12),
            selectButton.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
            selectButton.widthAnchor.constraint(equalToConstant: 80),
            selectButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        contentView = visualEffect
    }

    func showToolbar() {
        makeKeyAndOrderFront(nil)
    }

    @objc private func closeTapped() {
        StateFile.delete(at: Config.stateFilePath)
        NSApp.terminate(nil)
    }

    @objc private func selectAreaTapped() {
        // Hide toolbar during selection
        orderOut(nil)

        // Post notification that selection mode should begin
        NotificationCenter.default.post(name: .beginAreaSelection, object: nil)
    }
}

extension Notification.Name {
    static let beginAreaSelection = Notification.Name("beginAreaSelection")
    static let areaSelected = Notification.Name("areaSelected")
}
```

- [ ] **Step 3: Update main.swift to wire up AppDelegate**

`Sources/claude-vision-app/main.swift`:
```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 4: Build and verify**

Run: `swift build 2>&1`
Expected: Compiles successfully

- [ ] **Step 5: Commit**

```bash
git add Sources/claude-vision-app/
git commit -m "feat: add AppDelegate and floating toolbar window"
```

---

### Task 6: GUI — Selection Overlay

**Files:**
- Create: `Sources/claude-vision-app/SelectionOverlay.swift`
- Modify: `Sources/claude-vision-app/AppDelegate.swift`

- [ ] **Step 1: Create SelectionOverlay**

`Sources/claude-vision-app/SelectionOverlay.swift`:
```swift
import AppKit
import ClaudeVisionShared

class SelectionOverlay: NSWindow {
    private var selectionView: SelectionView!

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.3)
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces]

        selectionView = SelectionView(frame: screen.frame)
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }

    func beginSelection() {
        makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()
    }

    func endSelection() {
        NSCursor.pop()
        orderOut(nil)
    }
}

class SelectionView: NSView {
    private var startPoint: NSPoint?
    private var currentRect: NSRect?
    private let sizeLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)

        sizeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        sizeLabel.textColor = .white
        sizeLabel.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        sizeLabel.isBezeled = false
        sizeLabel.drawsBackground = true
        sizeLabel.wantsLayer = true
        sizeLabel.layer?.cornerRadius = 4
        sizeLabel.isHidden = true
        addSubview(sizeLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = nil
        sizeLabel.isHidden = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)

        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let w = abs(current.x - start.x)
        let h = abs(current.y - start.y)

        currentRect = NSRect(x: x, y: y, width: w, height: h)

        sizeLabel.stringValue = " \(Int(w)) × \(Int(h)) "
        sizeLabel.sizeToFit()
        sizeLabel.frame.origin = NSPoint(x: x, y: y + h + 4)

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = currentRect, rect.width > 10, rect.height > 10 else {
            // Too small — cancel
            startPoint = nil
            currentRect = nil
            sizeLabel.isHidden = true
            needsDisplay = true
            return
        }

        // Convert from view coordinates to screen coordinates
        let screenFrame = window?.screen?.frame ?? NSScreen.main!.frame
        let screenRect = NSRect(
            x: rect.origin.x + screenFrame.origin.x,
            y: screenFrame.height - rect.origin.y - rect.height + screenFrame.origin.y,
            width: rect.width,
            height: rect.height
        )

        let area = CaptureArea(
            x: Double(screenRect.origin.x),
            y: Double(screenRect.origin.y),
            width: Double(screenRect.width),
            height: Double(screenRect.height)
        )

        NotificationCenter.default.post(name: .areaSelected, object: area)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            startPoint = nil
            currentRect = nil
            sizeLabel.isHidden = true
            needsDisplay = true
            (window as? SelectionOverlay)?.endSelection()
            // Re-show toolbar
            NotificationCenter.default.post(name: .selectionCancelled, object: nil)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let rect = currentRect else { return }

        // Draw selection rectangle
        let path = NSBezierPath(rect: rect)
        NSColor(red: 0, green: 0.478, blue: 1, alpha: 0.15).setFill()
        path.fill()
        NSColor(red: 0, green: 0.478, blue: 1, alpha: 1).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}

extension Notification.Name {
    static let selectionCancelled = Notification.Name("selectionCancelled")
}
```

- [ ] **Step 2: Wire up selection in AppDelegate**

Add to `AppDelegate.swift` — add properties and notification observers:

Add these properties to AppDelegate:
```swift
var selectionOverlay: SelectionOverlay?
var borderWindow: BorderWindow?  // Will be implemented in Task 7
```

Add in `applicationDidFinishLaunching`, after creating the toolbar:
```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(beginSelection),
    name: .beginAreaSelection,
    object: nil
)
NotificationCenter.default.addObserver(
    self,
    selector: #selector(areaWasSelected(_:)),
    name: .areaSelected,
    object: nil
)
NotificationCenter.default.addObserver(
    self,
    selector: #selector(selectionWasCancelled),
    name: .selectionCancelled,
    object: nil
)
```

Add these methods to AppDelegate:
```swift
@objc func beginSelection() {
    let screen = NSScreen.main ?? NSScreen.screens[0]
    selectionOverlay = SelectionOverlay(screen: screen)
    selectionOverlay?.beginSelection()
}

@objc func areaWasSelected(_ notification: Notification) {
    guard let area = notification.object as? CaptureArea else { return }

    selectionOverlay?.endSelection()
    selectionOverlay = nil

    // Update state file with area
    let state = AppState(pid: ProcessInfo.processInfo.processIdentifier, area: area)
    do {
        try StateFile.write(state, to: Config.stateFilePath, createDirectory: Config.stateDirectory)
    } catch {
        NSLog("Failed to write area to state: \(error)")
    }

    // Show toolbar again
    toolbarWindow.showToolbar()

    // TODO: Show border window (Task 7)
}

@objc func selectionWasCancelled() {
    selectionOverlay?.endSelection()
    selectionOverlay = nil
    toolbarWindow.showToolbar()
}
```

- [ ] **Step 3: Build and verify**

Run: `swift build 2>&1`
Expected: Compiles (may warn about BorderWindow not yet existing — that's fine)

- [ ] **Step 4: Commit**

```bash
git add Sources/claude-vision-app/SelectionOverlay.swift Sources/claude-vision-app/AppDelegate.swift
git commit -m "feat: add selection overlay for drag-to-select area"
```

---

### Task 7: GUI — Border Window

**Files:**
- Create: `Sources/claude-vision-app/BorderWindow.swift`
- Modify: `Sources/claude-vision-app/AppDelegate.swift`

- [ ] **Step 1: Create BorderWindow**

`Sources/claude-vision-app/BorderWindow.swift`:
```swift
import AppKit
import ClaudeVisionShared

class BorderWindow: NSWindow {
    init(area: CaptureArea) {
        // Convert from CGWindowList coordinates (top-left origin) to AppKit (bottom-left origin)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenHeight = screen.frame.height

        let padding: CGFloat = 4 // Extra space for the border + label
        let labelHeight: CGFloat = 18
        let frame = NSRect(
            x: CGFloat(area.x) - padding,
            y: screenHeight - CGFloat(area.y) - CGFloat(area.height) - padding,
            width: CGFloat(area.width) + padding * 2,
            height: CGFloat(area.height) + padding * 2 + labelHeight
        )

        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        sharingType = .none  // Excluded from screen captures
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let borderView = BorderView(
            frame: NSRect(origin: .zero, size: frame.size),
            padding: padding,
            labelHeight: labelHeight
        )
        contentView = borderView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

class BorderView: NSView {
    let padding: CGFloat
    let labelHeight: CGFloat

    init(frame: NSRect, padding: CGFloat, labelHeight: CGFloat) {
        self.padding = padding
        self.labelHeight = labelHeight
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let blue = NSColor(red: 0, green: 0.478, blue: 1, alpha: 0.7)

        // Dashed border rectangle (inset by padding)
        let borderRect = NSRect(
            x: padding,
            y: padding,
            width: bounds.width - padding * 2,
            height: bounds.height - padding * 2 - labelHeight
        )

        let path = NSBezierPath(rect: borderRect)
        path.lineWidth = 2
        let dashPattern: [CGFloat] = [6, 4]
        path.setLineDash(dashPattern, count: 2, phase: 0)
        blue.setStroke()
        path.stroke()

        // "Claude Vision" label
        let labelString = NSAttributedString(
            string: "Claude Vision",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: blue,
                .backgroundColor: NSColor(red: 0, green: 0.478, blue: 1, alpha: 0.1),
            ]
        )
        let labelX = bounds.width - padding - labelString.size().width - 4
        let labelY = bounds.height - padding - labelHeight + 2
        labelString.draw(at: NSPoint(x: labelX, y: labelY))
    }
}
```

- [ ] **Step 2: Wire up border in AppDelegate**

In `AppDelegate.areaWasSelected(_:)`, replace the `// TODO: Show border window (Task 7)` comment:
```swift
// Show border window
borderWindow?.orderOut(nil)
borderWindow = BorderWindow(area: area)
borderWindow?.makeKeyAndOrderFront(nil)
```

- [ ] **Step 3: Build and verify**

Run: `swift build 2>&1`
Expected: Compiles successfully

- [ ] **Step 4: Commit**

```bash
git add Sources/claude-vision-app/BorderWindow.swift Sources/claude-vision-app/AppDelegate.swift
git commit -m "feat: add dashed border overlay for selected area"
```

---

### Task 8: Integration Test — Full End-to-End Flow

**Files:**
- No new files — manual verification

- [ ] **Step 1: Run all unit tests**

Run: `swift test 2>&1`
Expected: All tests pass

- [ ] **Step 2: Build release**

Run: `swift build -c release 2>&1`
Expected: Builds successfully

- [ ] **Step 3: Manual integration test**

Run through this sequence:
```bash
# Start the app
.build/release/claude-vision start
# Should print: "Claude Vision started. Use the toolbar to select an area."

# In another terminal, wait for selection
.build/release/claude-vision wait --timeout 120
# (Now use the toolbar to select an area on screen)
# Should print: "Area selected: WxH at (X, Y)"

# Capture the area
.build/release/claude-vision capture
# Should print: /var/folders/.../claude-vision-capture-XXXX.png

# Verify the screenshot
open $(!!:1)  # Opens the last printed path in Preview

# Stop the app
.build/release/claude-vision stop
# Should print: "Claude Vision stopped."
```

- [ ] **Step 4: Verify error cases**

```bash
# Capture without running app
.build/release/claude-vision capture
# Should print error to stderr and exit 1

# Stop when not running
.build/release/claude-vision stop
# Should print: "Claude Vision is not running." and exit 0

# Double start
.build/release/claude-vision start
.build/release/claude-vision start
# Second should print: "Claude Vision is already running (PID XXXX)"
```

- [ ] **Step 5: Commit any fixes, tag v0.1.0**

```bash
git tag v0.1.0
```

---

### Task 9: Install Script + Symlink

**Files:**
- Update: `.gitignore`

- [ ] **Step 1: Add build artifacts to .gitignore**

Append to `.gitignore`:
```
.build/
.superpowers/
```

- [ ] **Step 2: Build and symlink to /usr/local/bin**

```bash
swift build -c release
ln -sf $(pwd)/.build/release/claude-vision /usr/local/bin/claude-vision
ln -sf $(pwd)/.build/release/claude-vision-app /usr/local/bin/claude-vision-app
```

- [ ] **Step 3: Verify global CLI access**

Run: `claude-vision --help`
Expected: Shows help from anywhere in the terminal

- [ ] **Step 4: Commit**

```bash
git add .gitignore
git commit -m "chore: update .gitignore with build artifacts"
```
