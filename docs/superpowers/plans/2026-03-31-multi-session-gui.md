# Multi-Session GUI + About Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign Agent Vision from one-process-per-session to a single GUI process managing multiple sessions, with colored borders, session dropdown, full menu bar, and About window.

**Architecture:** Single GUI process discovered via `~/.agent-vision/gui.pid`. CLI `start` checks for living GUI before spawning. GUI polls `~/.agent-vision/sessions/` to discover/remove sessions. Each session gets an auto-assigned color from a fixed palette. `start` absorbs `wait` — blocks until area selected, then prints UUID + dimensions.

**Tech Stack:** Swift 6, AppKit, ArgumentParser, CoreGraphics, ApplicationServices, Vision

**Spec:** `docs/superpowers/specs/2026-03-31-multi-session-gui-design.md`

---

## File Map

### Shared library (`Sources/AgentVisionShared/`)

| File | Action | Purpose |
|------|--------|---------|
| `Config.swift` | Modify | Add `guiPidFilePath`, session color palette, color index assignment |
| `State.swift` | Modify | Add `colorIndex` to `AppState` |
| `SessionColors.swift` | Create | Color palette definition + assignment logic |
| `SkillContent.swift` | Modify | Update skill text (remove `wait`, update examples) |

### GUI target (`Sources/agent-vision/`)

| File | Action | Purpose |
|------|--------|---------|
| `CLI.swift` | Modify | Rewrite `Start` (merge `wait`, PID file logic), remove `Wait`, add gui.pid spawning |
| `GUIEntry.swift` | Modify | Remove `sessionID` parameter — GUI discovers sessions |
| `AppDelegate.swift` | Modify | Multi-session state, session scanner, per-session action watchers + borders |
| `ToolbarWindow.swift` | Modify | Add session dropdown picker |
| `BorderWindow.swift` | Modify | Accept color parameter, dynamic label |
| `ActionWatcher.swift` | Modify | No structural changes — just instantiated per session |
| `MenuBarSetup.swift` | Create | Full macOS menu bar (Agent Vision, Session, Help menus) |
| `AboutWindow.swift` | Create | About panel with version, author, link, update check |
| `SessionManager.swift` | Create | Central session registry: tracks sessions, colors, watchers, borders |

### Tests (`Tests/AgentVisionTests/`)

| File | Action | Purpose |
|------|--------|---------|
| `StateTests.swift` | Modify | Test `colorIndex` in AppState |
| `AgentVisionTests.swift` | Modify | Test `guiPidFilePath` path |
| `SessionColorTests.swift` | Create | Test color assignment logic |

### Root

| File | Action | Purpose |
|------|--------|---------|
| `SKILL.md` | Modify | Mirror SkillContent.swift changes |

---

## Task 1: Add color palette and `colorIndex` to shared types

**Files:**
- Create: `Sources/AgentVisionShared/SessionColors.swift`
- Modify: `Sources/AgentVisionShared/State.swift`
- Modify: `Sources/AgentVisionShared/Config.swift`
- Create: `Tests/AgentVisionTests/SessionColorTests.swift`
- Modify: `Tests/AgentVisionTests/StateTests.swift`

- [ ] **Step 1: Write failing test for color palette**

Create `Tests/AgentVisionTests/SessionColorTests.swift`:

```swift
import Testing
@testable import AgentVisionShared

@Suite struct SessionColorTests {
    @Test func paletteHasSevenColors() {
        #expect(SessionColors.palette.count == 7)
    }

    @Test func colorForIndexWrapsAround() {
        let first = SessionColors.color(forIndex: 0)
        let wrapped = SessionColors.color(forIndex: 7)
        #expect(first.red == wrapped.red)
        #expect(first.green == wrapped.green)
        #expect(first.blue == wrapped.blue)
    }

    @Test func nextColorIndexStartsAtZero() {
        let existing: [Int] = []
        #expect(SessionColors.nextColorIndex(existing: existing) == 0)
    }

    @Test func nextColorIndexIncrementsSequentially() {
        #expect(SessionColors.nextColorIndex(existing: [0]) == 1)
        #expect(SessionColors.nextColorIndex(existing: [0, 1]) == 2)
    }

    @Test func nextColorIndexFillsGaps() {
        // If session with color 1 was removed, next should still be max+1
        #expect(SessionColors.nextColorIndex(existing: [0, 2]) == 3)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SessionColorTests 2>&1 | tail -20`
Expected: Compilation error — `SessionColors` not defined

- [ ] **Step 3: Create SessionColors.swift**

Create `Sources/AgentVisionShared/SessionColors.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SessionColorTests 2>&1 | tail -20`
Expected: All 5 tests pass

- [ ] **Step 5: Write failing test for colorIndex in AppState**

Add to `Tests/AgentVisionTests/StateTests.swift`:

```swift
func testStateWithColorIndex() throws {
    let state = AppState(pid: 1, area: nil, colorIndex: 3)
    try StateFile.write(state, to: testFile, createDirectory: testDir)
    let read = try XCTUnwrap(StateFile.read(from: testFile))
    XCTAssertEqual(read.colorIndex, 3)
}

func testStateWithoutColorIndexDefaultsToZero() throws {
    // Simulate old state.json without colorIndex field
    let json = #"{"pid":1}"#
    try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    try json.data(using: .utf8)!.write(to: testFile)
    let read = try XCTUnwrap(StateFile.read(from: testFile))
    XCTAssertEqual(read.colorIndex, 0)
}
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `swift test --filter StateTests 2>&1 | tail -20`
Expected: Compilation error — `AppState` has no `colorIndex` parameter

- [ ] **Step 7: Add `colorIndex` to AppState**

Modify `Sources/AgentVisionShared/State.swift` — update `AppState`:

```swift
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
```

- [ ] **Step 8: Add `guiPidFilePath` to Config**

Add to `Sources/AgentVisionShared/Config.swift` after `sessionsDirectory`:

```swift
public static let guiPidFilePath = stateDirectory.appendingPathComponent("gui.pid")
```

- [ ] **Step 9: Add guiPidFilePath test**

Add to `Tests/AgentVisionTests/AgentVisionTests.swift`:

```swift
@Test func testGuiPidFilePath() {
    #expect(Config.guiPidFilePath.lastPathComponent == "gui.pid")
    #expect(Config.guiPidFilePath.path.contains(".agent-vision"))
}
```

- [ ] **Step 10: Run all tests**

Run: `swift test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 11: Commit**

```bash
git add Sources/AgentVisionShared/SessionColors.swift Sources/AgentVisionShared/State.swift Sources/AgentVisionShared/Config.swift Tests/AgentVisionTests/SessionColorTests.swift Tests/AgentVisionTests/StateTests.swift Tests/AgentVisionTests/AgentVisionTests.swift
git commit -m "feat: add session color palette, colorIndex to AppState, guiPidFilePath"
```

---

## Task 2: Rewrite `start` to merge `wait`, add PID file logic, remove `Wait` command

**Files:**
- Modify: `Sources/agent-vision/CLI.swift`

- [ ] **Step 1: Rewrite the `Start` struct**

Replace the entire `Start` struct in `CLI.swift` with:

```swift
struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Start a session — launches GUI if needed, waits for area selection")

    @Option(name: .long, help: "Timeout in seconds (default: 60)")
    var timeout: Int = 60

    func run() throws {
        checkForUpdate(owner: "rvanbaalen", repo: "agent-vision")
        Config.cleanStaleSessions()

        let sessionID = UUID().uuidString.lowercased()
        let sessionDir = Config.sessionDirectory(for: sessionID)

        // Determine next color index from existing sessions
        let existingColors = (try? existingSessionColorIndices()) ?? []
        let colorIndex = SessionColors.nextColorIndex(existing: existingColors)

        let guiPid = readGuiPid()
        let guiAlive = guiPid != nil && StateFile.isProcessRunning(pid: guiPid!)

        // Write session state BEFORE spawning GUI so GUI can discover it
        let state = AppState(pid: guiPid ?? ProcessInfo.processInfo.processIdentifier, area: nil, colorIndex: colorIndex)
        try StateFile.write(state, to: Config.stateFilePath(for: sessionID), createDirectory: sessionDir)

        if !guiAlive {
            let pid = try spawnGUI()
            writeGuiPid(pid)
            // Update session state with actual GUI PID
            let updatedState = AppState(pid: pid, area: nil, colorIndex: colorIndex)
            try StateFile.write(updatedState, to: Config.stateFilePath(for: sessionID), createDirectory: sessionDir)
        }

        // Block until area is selected (merged from old Wait command)
        let statePath = Config.stateFilePath(for: sessionID)
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))

        while Date() < deadline {
            guard let currentState = try StateFile.read(from: statePath) else {
                fputs("Session disappeared unexpectedly.\n", stderr)
                throw ExitCode.failure
            }

            if let area = currentState.area {
                print(sessionID)
                print("Area selected: \(Int(area.width))x\(Int(area.height)) at (\(Int(area.x)), \(Int(area.y)))")
                return
            }

            Thread.sleep(forTimeInterval: 0.5)
        }

        fputs("No area selected within \(timeout)s\n", stderr)
        // Clean up the session we created since it was never used
        try? FileManager.default.removeItem(at: sessionDir)
        throw ExitCode.failure
    }
}

// MARK: - GUI PID file helpers

func readGuiPid() -> Int32? {
    guard let data = try? Data(contentsOf: Config.guiPidFilePath),
          let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          let pid = Int32(str) else { return nil }
    return pid
}

func writeGuiPid(_ pid: Int32) {
    try? FileManager.default.createDirectory(at: Config.stateDirectory, withIntermediateDirectories: true)
    try? "\(pid)\n".data(using: .utf8)?.write(to: Config.guiPidFilePath, options: .atomic)
}

func existingSessionColorIndices() throws -> [Int] {
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(at: Config.sessionsDirectory, includingPropertiesForKeys: nil) else {
        return []
    }
    var indices: [Int] = []
    for entry in entries {
        let statePath = entry.appendingPathComponent("state.json")
        if let state = try? StateFile.read(from: statePath) {
            indices.append(state.colorIndex)
        }
    }
    return indices
}

func spawnGUI() throws -> Int32 {
    var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    var size = UInt32(MAXPATHLEN)
    guard _NSGetExecutablePath(&pathBuffer, &size) == 0 else {
        throw ValidationError("Cannot determine executable path.")
    }
    let selfPath = String(cString: pathBuffer)
    let selfURL = URL(fileURLWithPath: selfPath).resolvingSymlinksInPath()

    let process = Process()
    process.executableURL = selfURL
    process.arguments = ["--gui"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    return process.processIdentifier
}
```

- [ ] **Step 2: Remove the `Wait` struct entirely**

Delete the entire `struct Wait: ParsableCommand { ... }` block from `CLI.swift`.

- [ ] **Step 3: Remove `Wait.self` from subcommands**

Change the subcommands array in `AgentVision` from:

```swift
subcommands: [Start.self, Wait.self, Capture.self, Calibrate.self, Preview.self, Stop.self, Control.self, Elements.self, SkillInfo.self]
```

to:

```swift
subcommands: [Start.self, Capture.self, Calibrate.self, Preview.self, Stop.self, Control.self, Elements.self, SkillInfo.self]
```

- [ ] **Step 4: Update `Stop` to remove session directory only (no SIGTERM)**

Replace the `Stop` struct:

```swift
struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop a session")

    @Option(name: .long, help: "Session ID")
    var session: String

    func run() throws {
        try validateSession(session)
        // Just remove session directory — GUI detects removal via polling
        try? FileManager.default.removeItem(at: Config.sessionDirectory(for: session))
        print("Session stopped.")
    }
}
```

- [ ] **Step 5: Update `AgentVision.run()` — remove `--session` flag from `--gui`**

Replace the `AgentVision` struct's `run()` and remove the `session` option:

```swift
@main
struct AgentVision: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent-vision",
        abstract: "Give AI agents eyes on your screen",
        subcommands: [Start.self, Capture.self, Calibrate.self, Preview.self, Stop.self, Control.self, Elements.self, SkillInfo.self]
    )

    @Flag(name: .long, help: .hidden)
    var gui: Bool = false

    mutating func run() throws {
        if gui {
            startGUI()
            // startGUI never returns — it calls NSApp.run()
        }
        throw CleanExit.helpRequest()
    }
}
```

- [ ] **Step 6: Build to verify compilation**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds (with existing deprecation warnings only)

- [ ] **Step 7: Commit**

```bash
git add Sources/agent-vision/CLI.swift
git commit -m "feat: merge start+wait, add PID file logic, remove Wait command"
```

---

## Task 3: Rewrite `GUIEntry.swift` — sessionless GUI launch

**Files:**
- Modify: `Sources/agent-vision/GUIEntry.swift`

- [ ] **Step 1: Rewrite GUIEntry to not require a session ID**

Replace the entire content of `Sources/agent-vision/GUIEntry.swift`:

```swift
import AppKit
import AgentVisionShared

/// Starts the AppKit GUI event loop. This function never returns.
func startGUI() -> Never {
    NSLog("[agent-vision] App starting in GUI mode")

    NSSetUncaughtExceptionHandler { exception in
        NSLog("[agent-vision] UNCAUGHT EXCEPTION: \(exception)")
        NSLog("[agent-vision] Stack trace: \(exception.callStackSymbols.joined(separator: "\n"))")
    }

    for sig: Int32 in [SIGABRT, SIGBUS, SIGSEGV, SIGILL] {
        signal(sig) { sigNum in
            NSLog("[agent-vision] FATAL SIGNAL \(sigNum) received")
            signal(sigNum, SIG_DFL)
            raise(sigNum)
        }
    }

    // Write gui.pid
    let pid = ProcessInfo.processInfo.processIdentifier
    writeGuiPid(pid)

    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    MainActor.assumeIsolated {
        let delegate = AppDelegate()
        app.delegate = delegate
    }

    NSLog("[agent-vision] Running app loop")
    app.run()

    // Cleanup on exit
    try? FileManager.default.removeItem(at: Config.guiPidFilePath)
    exit(0)
}
```

Note: `setActivationPolicy(.regular)` instead of `.accessory` — this gives us a full menu bar.

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/agent-vision/GUIEntry.swift
git commit -m "feat: GUI launches without session ID, uses .regular activation for menu bar"
```

---

## Task 4: Create `SessionManager.swift` — central session registry

**Files:**
- Create: `Sources/agent-vision/SessionManager.swift`

- [ ] **Step 1: Create the session manager**

Create `Sources/agent-vision/SessionManager.swift`:

```swift
import AppKit
import AgentVisionShared

/// Tracks active sessions, their colors, border windows, and action watchers.
@MainActor
class SessionManager {
    struct TrackedSession {
        let sessionID: String
        let colorIndex: Int
        var area: CaptureArea?
        var borderWindow: BorderWindow?
        var actionWatcher: ActionWatcher
    }

    private(set) var sessions: [String: TrackedSession] = [:]
    private var scanTimer: Timer?
    var onSessionsChanged: (() -> Void)?
    var onActionFeedback: ((ActionRequest, CaptureArea) -> Void)?

    /// The session ID currently selected in the toolbar dropdown.
    var selectedSessionID: String?

    func startScanning() {
        NSLog("[agent-vision] SessionManager: starting session directory scanner")
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scan()
            }
        }
        // Run an immediate scan
        scan()
    }

    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    private func scan() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: Config.sessionsDirectory, includingPropertiesForKeys: nil
        ) else { return }

        let directoryIDs = Set(entries.map { $0.lastPathComponent })
        let trackedIDs = Set(sessions.keys)

        // Detect new sessions
        for entry in entries {
            let sid = entry.lastPathComponent
            guard Config.isValidSessionID(sid), !trackedIDs.contains(sid) else { continue }
            let statePath = Config.stateFilePath(for: sid)
            guard let state = try? StateFile.read(from: statePath) else { continue }
            adoptSession(id: sid, state: state)
        }

        // Detect removed sessions
        for sid in trackedIDs where !directoryIDs.contains(sid) {
            removeSession(id: sid)
        }

        // Update areas for existing sessions (detect area selection)
        for (sid, tracked) in sessions {
            let statePath = Config.stateFilePath(for: sid)
            guard let state = try? StateFile.read(from: statePath) else { continue }
            if state.area != nil && tracked.area == nil {
                // Area was just selected
                sessions[sid]?.area = state.area
                let color = SessionColors.color(forIndex: tracked.colorIndex)
                sessions[sid]?.borderWindow?.orderOut(nil)
                sessions[sid]?.borderWindow = BorderWindow(area: state.area!, sessionColor: color, sessionLabel: borderLabel(for: sid))
                sessions[sid]?.borderWindow?.makeKeyAndOrderFront(nil)
                onSessionsChanged?()
            }
        }
    }

    private func adoptSession(id: String, state: AppState) {
        NSLog("[agent-vision] SessionManager: adopting session \(id) (color=\(state.colorIndex))")

        let watcher = ActionWatcher(sessionID: id)
        watcher.start { [weak self] action, area in
            self?.onActionFeedback?(action, area)
        }

        var tracked = TrackedSession(
            sessionID: id,
            colorIndex: state.colorIndex,
            area: state.area,
            actionWatcher: watcher
        )

        if let area = state.area {
            let color = SessionColors.color(forIndex: state.colorIndex)
            tracked.borderWindow = BorderWindow(area: area, sessionColor: color, sessionLabel: borderLabel(for: id))
            tracked.borderWindow?.makeKeyAndOrderFront(nil)
        }

        sessions[id] = tracked

        // Auto-switch to newest session
        selectedSessionID = id
        onSessionsChanged?()
    }

    private func removeSession(id: String) {
        NSLog("[agent-vision] SessionManager: removing session \(id)")
        sessions[id]?.actionWatcher.stop()
        sessions[id]?.borderWindow?.orderOut(nil)
        sessions.removeValue(forKey: id)

        if selectedSessionID == id {
            selectedSessionID = sessions.keys.first
        }

        onSessionsChanged?()

        // Quit if no sessions remain
        if sessions.isEmpty {
            NSLog("[agent-vision] SessionManager: no sessions left — quitting")
            try? FileManager.default.removeItem(at: Config.guiPidFilePath)
            NSApp.terminate(nil)
        }
    }

    func stopSession(id: String) {
        try? FileManager.default.removeItem(at: Config.sessionDirectory(for: id))
        // scan() will pick up the removal on next tick
    }

    func stopAllSessions() {
        for sid in sessions.keys {
            try? FileManager.default.removeItem(at: Config.sessionDirectory(for: sid))
        }
    }

    /// Returns the label to show on the border for a session.
    func borderLabel(for sessionID: String) -> String {
        if sessions.count <= 1 {
            return "Agent Vision"
        }
        return String(sessionID.prefix(8))
    }

    /// Updates all border labels when session count changes (1 → many or many → 1).
    func refreshBorderLabels() {
        for (sid, tracked) in sessions {
            tracked.borderWindow?.updateLabel(borderLabel(for: sid))
        }
    }

    /// Ordered list of sessions for display (sorted by creation = directory order).
    var orderedSessions: [TrackedSession] {
        sessions.values.sorted { $0.sessionID < $1.sessionID }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build fails — `BorderWindow` doesn't accept `sessionColor`/`sessionLabel` yet. That's expected; Task 5 will fix it.

- [ ] **Step 3: Commit (WIP)**

```bash
git add Sources/agent-vision/SessionManager.swift
git commit -m "wip: add SessionManager for multi-session tracking"
```

---

## Task 5: Update `BorderWindow.swift` — per-session color and dynamic label

**Files:**
- Modify: `Sources/agent-vision/BorderWindow.swift`

- [ ] **Step 1: Rewrite BorderWindow to accept color and label**

Replace the entire content of `Sources/agent-vision/BorderWindow.swift`:

```swift
import AppKit
import AgentVisionShared

class BorderWindow: NSWindow {
    private var borderView: BorderView!

    init(area: CaptureArea, sessionColor: SessionColor, sessionLabel: String) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenHeight = screen.frame.height

        let padding: CGFloat = 4
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
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        borderView = BorderView(
            frame: NSRect(origin: .zero, size: frame.size),
            padding: padding,
            labelHeight: labelHeight,
            color: NSColor(red: sessionColor.red, green: sessionColor.green, blue: sessionColor.blue, alpha: 0.7),
            label: sessionLabel
        )
        contentView = borderView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateLabel(_ newLabel: String) {
        borderView.label = newLabel
        borderView.needsDisplay = true
    }
}

class BorderView: NSView {
    let padding: CGFloat
    let labelHeight: CGFloat
    let color: NSColor
    var label: String

    init(frame: NSRect, padding: CGFloat, labelHeight: CGFloat, color: NSColor, label: String) {
        self.padding = padding
        self.labelHeight = labelHeight
        self.color = color
        self.label = label
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Dashed border rectangle
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
        color.setStroke()
        path.stroke()

        // Label
        let labelString = NSAttributedString(
            string: label,
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: color,
                .backgroundColor: color.withAlphaComponent(0.15),
            ]
        )
        let labelX = bounds.width - padding - labelString.size().width - 4
        let labelY = bounds.height - padding - labelHeight + 2
        labelString.draw(at: NSPoint(x: labelX, y: labelY))
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds (SessionManager references now resolve)

- [ ] **Step 3: Commit**

```bash
git add Sources/agent-vision/BorderWindow.swift
git commit -m "feat: BorderWindow accepts session color and dynamic label"
```

---

## Task 6: Rewrite `AppDelegate.swift` — multi-session via SessionManager

**Files:**
- Modify: `Sources/agent-vision/AppDelegate.swift`

- [ ] **Step 1: Rewrite AppDelegate for multi-session**

Replace the entire content of `Sources/agent-vision/AppDelegate.swift`:

```swift
import AppKit
import AgentVisionShared

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var toolbarWindow: ToolbarWindow!
    var selectionOverlay: SelectionOverlay?
    var windowSelectionController: WindowSelectionController?
    var feedbackWindow: ActionFeedbackWindow?
    let sessionManager = SessionManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[agent-vision] applicationDidFinishLaunching")

        // Set up signal handler for cleanup
        signal(SIGTERM) { _ in
            try? FileManager.default.removeItem(at: Config.guiPidFilePath)
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }

        // Set up menu bar
        setupMenuBar()

        // Create and show toolbar
        NSLog("[agent-vision] Creating toolbar window")
        toolbarWindow = ToolbarWindow()
        toolbarWindow.sessionManager = sessionManager
        toolbarWindow.showToolbar()

        // Register for notifications
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
            selector: #selector(beginWindowSelection),
            name: .beginWindowSelection,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionWasCancelled),
            name: .selectionCancelled,
            object: nil
        )

        // Start session manager
        sessionManager.onSessionsChanged = { [weak self] in
            self?.toolbarWindow.refreshDropdown()
            self?.sessionManager.refreshBorderLabels()
        }
        sessionManager.onActionFeedback = { [weak self] action, area in
            self?.showActionFeedback(action: action, area: area)
        }
        sessionManager.startScanning()

        NSLog("[agent-vision] App launch complete, session scanner started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("[agent-vision] applicationWillTerminate — cleaning up")
        sessionManager.stopScanning()
        sessionManager.stopAllSessions()
        try? FileManager.default.removeItem(at: Config.guiPidFilePath)
        NSLog("[agent-vision] Cleanup complete")
    }

    func showActionFeedback(action: ActionRequest, area: CaptureArea) {
        if feedbackWindow == nil {
            feedbackWindow = ActionFeedbackWindow()
        }

        let screenPoint: CGPoint
        switch action {
        case .click(let pt):
            screenPoint = CGPoint(x: area.x + pt.x, y: area.y + pt.y)
        case .scroll(_, let pt):
            screenPoint = CGPoint(x: area.x + pt.x, y: area.y + pt.y)
        case .drag(let from, _):
            screenPoint = CGPoint(x: area.x + from.x, y: area.y + from.y)
        case .type, .key, .discoverElements, .clickElement, .typeElement:
            screenPoint = CGPoint(x: area.x + area.width / 2, y: area.y + area.height / 2)
        }

        feedbackWindow?.showRipple(at: screenPoint)
    }

    @objc func beginSelection() {
        NSLog("[agent-vision] beginSelection — area drag mode")
        let screen = NSScreen.main ?? NSScreen.screens[0]
        selectionOverlay = SelectionOverlay(screen: screen)
        selectionOverlay?.beginSelection()
    }

    @objc func beginWindowSelection() {
        NSLog("[agent-vision] beginWindowSelection — window pick mode")
        windowSelectionController = WindowSelectionController()
        windowSelectionController?.begin()
    }

    @objc func areaWasSelected(_ notification: Notification) {
        guard let area = notification.object as? CaptureArea else {
            NSLog("[agent-vision] areaWasSelected — notification had no CaptureArea!")
            return
        }
        NSLog("[agent-vision] areaWasSelected — \(Int(area.width))x\(Int(area.height)) at (\(Int(area.x)),\(Int(area.y)))")

        selectionOverlay?.endSelection()
        selectionOverlay = nil
        windowSelectionController?.end()
        windowSelectionController = nil

        // Write area to the selected session's state file
        guard let sid = sessionManager.selectedSessionID,
              let tracked = sessionManager.sessions[sid] else {
            NSLog("[agent-vision] areaWasSelected — no selected session")
            toolbarWindow.showToolbar()
            return
        }

        let guiPid = ProcessInfo.processInfo.processIdentifier
        let state = AppState(pid: guiPid, area: area, colorIndex: tracked.colorIndex)
        do {
            try StateFile.write(state, to: Config.stateFilePath(for: sid), createDirectory: Config.sessionDirectory(for: sid))
        } catch {
            NSLog("[agent-vision] ERROR: Failed to write area to state: \(error)")
        }

        toolbarWindow.showToolbar()
        // Session scanner will pick up the area change and create the border
    }

    @objc func selectionWasCancelled() {
        NSLog("[agent-vision] selectionWasCancelled")
        selectionOverlay?.endSelection()
        selectionOverlay = nil
        windowSelectionController?.end()
        windowSelectionController = nil
        toolbarWindow.showToolbar()
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build fails — `setupMenuBar()` not defined, `ToolbarWindow` doesn't have `sessionManager`/`refreshDropdown()` yet. Expected; Tasks 7 and 8 will fix.

- [ ] **Step 3: Commit (WIP)**

```bash
git add Sources/agent-vision/AppDelegate.swift
git commit -m "wip: rewrite AppDelegate for multi-session via SessionManager"
```

---

## Task 7: Update `ToolbarWindow.swift` — session dropdown picker

**Files:**
- Modify: `Sources/agent-vision/ToolbarWindow.swift`

- [ ] **Step 1: Rewrite ToolbarWindow with session dropdown**

Replace the entire content of `Sources/agent-vision/ToolbarWindow.swift`:

```swift
import AppKit
import AgentVisionShared

class ToolbarWindow: NSPanel {
    private var selectButton: NSButton!
    private var dropdownButton: NSButton!
    weak var sessionManager: SessionManager?

    init() {
        let toolbarWidth: CGFloat = 560
        let toolbarHeight: CGFloat = 52

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - toolbarWidth / 2
        let y = screenFrame.minY + 20

        let contentRect = NSRect(x: x, y: y, width: toolbarWidth, height: toolbarHeight)

        super.init(
            contentRect: contentRect,
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

        setupContent(toolbarWidth: toolbarWidth, toolbarHeight: toolbarHeight)
    }

    func refreshDropdown() {
        guard let sm = sessionManager, let sid = sm.selectedSessionID,
              let tracked = sm.sessions[sid] else {
            dropdownButton?.title = "No sessions"
            return
        }
        let dims: String
        if let area = tracked.area {
            dims = "\(Int(area.width))\u{00d7}\(Int(area.height))"
        } else {
            dims = "awaiting selection"
        }
        let prefix = String(sid.prefix(8))
        dropdownButton?.title = "\(prefix) · \(dims)"

        // Tint dropdown background to session color
        let color = SessionColors.color(forIndex: tracked.colorIndex)
        dropdownButton?.layer?.backgroundColor = NSColor(
            red: color.red, green: color.green, blue: color.blue, alpha: 0.15
        ).cgColor
    }

    private func setupContent(toolbarWidth: CGFloat, toolbarHeight: CGFloat) {
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: toolbarWidth, height: toolbarHeight))
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true

        // Title label
        let titleLabel = NSTextField(labelWithString: "Agent Vision")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        // Separator 1
        let sep1 = NSBox(frame: .zero)
        sep1.translatesAutoresizingMaskIntoConstraints = false
        sep1.boxType = .separator

        // Session dropdown
        let dropdown = HoverButton(frame: .zero)
        dropdown.translatesAutoresizingMaskIntoConstraints = false
        dropdown.bezelStyle = .regularSquare
        dropdown.isBordered = false
        dropdown.title = "No sessions"
        dropdown.font = .systemFont(ofSize: 11, weight: .medium)
        dropdown.contentTintColor = .labelColor
        dropdown.target = self
        dropdown.action = #selector(dropdownTapped(_:))
        dropdown.wantsLayer = true
        dropdown.layer?.cornerRadius = 6
        let dropBg = NSColor.white.withAlphaComponent(0.08).cgColor
        dropdown.layer?.backgroundColor = dropBg
        dropdown.restingBackground = dropBg
        self.dropdownButton = dropdown

        // Separator 2
        let sep2 = NSBox(frame: .zero)
        sep2.translatesAutoresizingMaskIntoConstraints = false
        sep2.boxType = .separator

        // Select Area button
        let selectBtn = HoverButton(frame: .zero)
        selectBtn.translatesAutoresizingMaskIntoConstraints = false
        selectBtn.bezelStyle = .regularSquare
        selectBtn.isBordered = false
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        selectBtn.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "Select Area")?.withSymbolConfiguration(symbolConfig)
        selectBtn.imagePosition = .imageLeading
        selectBtn.imageScaling = .scaleNone
        selectBtn.title = "Select Area"
        selectBtn.font = .systemFont(ofSize: 12, weight: .medium)
        selectBtn.contentTintColor = .labelColor
        selectBtn.target = self
        selectBtn.action = #selector(selectAreaTapped)
        selectBtn.wantsLayer = true
        selectBtn.layer?.cornerRadius = 6
        let btnBg = NSColor.white.withAlphaComponent(0.08).cgColor
        selectBtn.layer?.backgroundColor = btnBg
        selectBtn.restingBackground = btnBg
        self.selectButton = selectBtn

        // Select Window button
        let windowBtn = HoverButton(frame: .zero)
        windowBtn.translatesAutoresizingMaskIntoConstraints = false
        windowBtn.bezelStyle = .regularSquare
        windowBtn.isBordered = false
        let windowSymbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        windowBtn.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Select Window")?.withSymbolConfiguration(windowSymbolConfig)
        windowBtn.imagePosition = .imageLeading
        windowBtn.imageScaling = .scaleNone
        windowBtn.title = "Select Window"
        windowBtn.font = .systemFont(ofSize: 12, weight: .medium)
        windowBtn.contentTintColor = .labelColor
        windowBtn.target = self
        windowBtn.action = #selector(selectWindowTapped)
        windowBtn.wantsLayer = true
        windowBtn.layer?.cornerRadius = 6
        windowBtn.layer?.backgroundColor = btnBg
        windowBtn.restingBackground = btnBg

        // Close button
        let closeButton = NSButton(frame: .zero)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.imageScaling = .scaleProportionallyUpOrDown
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.contentTintColor = .tertiaryLabelColor

        visualEffect.addSubview(titleLabel)
        visualEffect.addSubview(sep1)
        visualEffect.addSubview(dropdown)
        visualEffect.addSubview(sep2)
        visualEffect.addSubview(selectBtn)
        visualEffect.addSubview(windowBtn)
        visualEffect.addSubview(closeButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),

            sep1.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 10),
            sep1.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
            sep1.heightAnchor.constraint(equalToConstant: 22),
            sep1.widthAnchor.constraint(equalToConstant: 1),

            dropdown.leadingAnchor.constraint(equalTo: sep1.trailingAnchor, constant: 8),
            dropdown.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),

            sep2.leadingAnchor.constraint(equalTo: dropdown.trailingAnchor, constant: 8),
            sep2.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
            sep2.heightAnchor.constraint(equalToConstant: 22),
            sep2.widthAnchor.constraint(equalToConstant: 1),

            selectBtn.leadingAnchor.constraint(equalTo: sep2.trailingAnchor, constant: 8),
            selectBtn.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),

            windowBtn.leadingAnchor.constraint(equalTo: selectBtn.trailingAnchor, constant: 6),
            windowBtn.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),

            closeButton.leadingAnchor.constraint(greaterThanOrEqualTo: windowBtn.trailingAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -14),
            closeButton.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),
        ])

        contentView = visualEffect
    }

    func showToolbar() {
        makeKeyAndOrderFront(nil)
    }

    @objc private func closeTapped() {
        // Stop the selected session; if last, app quits via SessionManager
        guard let sm = sessionManager, let sid = sm.selectedSessionID else {
            NSApp.terminate(nil)
            return
        }
        sm.stopSession(id: sid)
    }

    @objc private func selectAreaTapped() {
        orderOut(nil)
        NotificationCenter.default.post(name: .beginAreaSelection, object: nil)
    }

    @objc private func selectWindowTapped() {
        orderOut(nil)
        NotificationCenter.default.post(name: .beginWindowSelection, object: nil)
    }

    @objc private func dropdownTapped(_ sender: NSButton) {
        guard let sm = sessionManager else { return }
        let menu = NSMenu()

        for tracked in sm.orderedSessions {
            let color = SessionColors.color(forIndex: tracked.colorIndex)
            let prefix = String(tracked.sessionID.prefix(8))
            let dims: String
            if let area = tracked.area {
                dims = "\(Int(area.width))\u{00d7}\(Int(area.height))"
            } else {
                dims = "awaiting selection"
            }

            let item = NSMenuItem(title: "\(prefix) · \(dims)", action: #selector(selectSession(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tracked.sessionID

            // Color dot via attributed title
            let dot = NSMutableAttributedString(string: "● ", attributes: [
                .foregroundColor: NSColor(red: color.red, green: color.green, blue: color.blue, alpha: 1),
                .font: NSFont.systemFont(ofSize: 12),
            ])
            dot.append(NSAttributedString(string: "\(prefix) · \(dims)", attributes: [
                .font: NSFont.systemFont(ofSize: 12),
            ]))
            item.attributedTitle = dot

            if tracked.sessionID == sm.selectedSessionID {
                item.state = .on
            }

            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @objc private func selectSession(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String else { return }
        sessionManager?.selectedSessionID = sid
        refreshDropdown()
    }
}

// Button cell that adds internal padding around content
class PaddedButtonCell: NSButtonCell {
    var inset = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        return NSRect(
            x: rect.origin.x + inset.left,
            y: rect.origin.y + inset.bottom,
            width: rect.width - inset.left - inset.right,
            height: rect.height - inset.top - inset.bottom
        )
    }

    override func cellSize(forBounds rect: NSRect) -> NSSize {
        var size = super.cellSize(forBounds: rect)
        size.width += inset.left + inset.right
        size.height += inset.top + inset.bottom
        return size
    }
}

// Button with hover highlight and internal padding
class HoverButton: NSButton {
    private var trackingArea: NSTrackingArea?
    var restingBackground: CGColor?

    override class var cellClass: AnyClass? {
        get { PaddedButtonCell.self }
        set {}
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = restingBackground
    }
}

extension Notification.Name {
    static let beginAreaSelection = Notification.Name("beginAreaSelection")
    static let beginWindowSelection = Notification.Name("beginWindowSelection")
    static let areaSelected = Notification.Name("areaSelected")
    static let selectionCancelled = Notification.Name("selectionCancelled")
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build fails — `setupMenuBar()` still undefined. Task 8 next.

- [ ] **Step 3: Commit (WIP)**

```bash
git add Sources/agent-vision/ToolbarWindow.swift
git commit -m "feat: toolbar with session dropdown picker"
```

---

## Task 8: Create `MenuBarSetup.swift` and `AboutWindow.swift`

**Files:**
- Create: `Sources/agent-vision/MenuBarSetup.swift`
- Create: `Sources/agent-vision/AboutWindow.swift`

- [ ] **Step 1: Create MenuBarSetup.swift**

Create `Sources/agent-vision/MenuBarSetup.swift`:

```swift
import AppKit
import AgentVisionShared

extension AppDelegate {
    func setupMenuBar() {
        let mainMenu = NSMenu()

        // Agent Vision menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Agent Vision", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Agent Vision", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Session menu
        let sessionMenuItem = NSMenuItem()
        let sessionMenu = NSMenu(title: "Session")
        sessionMenuItem.submenu = sessionMenu
        mainMenu.addItem(sessionMenuItem)

        // Help menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Agent Vision Help", action: #selector(openHelp), keyEquivalent: "")
        helpMenu.addItem(withTitle: "View on Website", action: #selector(openWebsite), keyEquivalent: "")
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func showAbout() {
        AboutWindow.shared.showAbout()
    }

    @objc func checkUpdates() {
        AboutWindow.shared.showAbout()
        AboutWindow.shared.triggerUpdateCheck()
    }

    @objc func openHelp() {
        if let url = URL(string: "https://robinvanbaalen.nl/agent-vision") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openWebsite() {
        if let url = URL(string: "https://robinvanbaalen.nl/agent-vision") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Session menu updates

extension AppDelegate {
    /// Called by SessionManager.onSessionsChanged to rebuild the Session menu.
    func rebuildSessionMenu() {
        guard let mainMenu = NSApp.mainMenu,
              mainMenu.items.count >= 2,
              let sessionMenu = mainMenu.items[1].submenu else { return }

        sessionMenu.removeAllItems()

        let header = NSMenuItem(title: "Active Sessions", action: nil, keyEquivalent: "")
        header.isEnabled = false
        sessionMenu.addItem(header)

        for tracked in sessionManager.orderedSessions {
            let color = SessionColors.color(forIndex: tracked.colorIndex)
            let prefix = String(tracked.sessionID.prefix(8))
            let dims: String
            if let area = tracked.area {
                dims = "\(Int(area.width))\u{00d7}\(Int(area.height))"
            } else {
                dims = "awaiting selection"
            }

            let item = NSMenuItem(title: "\(prefix) · \(dims)", action: nil, keyEquivalent: "")
            let dot = NSMutableAttributedString(string: "● ", attributes: [
                .foregroundColor: NSColor(red: color.red, green: color.green, blue: color.blue, alpha: 1),
                .font: NSFont.systemFont(ofSize: 12),
            ])
            dot.append(NSAttributedString(string: "\(prefix) · \(dims)", attributes: [
                .font: NSFont.systemFont(ofSize: 12),
            ]))
            item.attributedTitle = dot
            sessionMenu.addItem(item)
        }

        sessionMenu.addItem(.separator())

        let stopSelected = NSMenuItem(title: "Stop Selected Session", action: #selector(stopSelectedSession), keyEquivalent: "")
        stopSelected.target = self
        sessionMenu.addItem(stopSelected)

        let stopAll = NSMenuItem(title: "Stop All Sessions", action: #selector(stopAllSessions), keyEquivalent: "")
        stopAll.target = self
        sessionMenu.addItem(stopAll)
    }

    @objc func stopSelectedSession() {
        guard let sid = sessionManager.selectedSessionID else { return }
        sessionManager.stopSession(id: sid)
    }

    @objc func stopAllSessions() {
        sessionManager.stopAllSessions()
    }
}
```

- [ ] **Step 2: Create AboutWindow.swift**

Create `Sources/agent-vision/AboutWindow.swift`:

```swift
import AppKit
import AgentVisionShared

@MainActor
class AboutWindow {
    static let shared = AboutWindow()

    private var window: NSPanel?
    private var updateLabel: NSTextField?

    func showAbout() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "About Agent Vision"
        panel.isFloatingPanel = true
        panel.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 320))

        // App icon
        let iconView = NSImageView(frame: NSRect(x: 118, y: 230, width: 64, height: 64))
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            iconView.image = appIcon
        }
        content.addSubview(iconView)

        // App name
        let nameLabel = NSTextField(labelWithString: "Agent Vision")
        nameLabel.frame = NSRect(x: 0, y: 200, width: 300, height: 24)
        nameLabel.alignment = .center
        nameLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        content.addSubview(nameLabel)

        // Version
        let versionLabel = NSTextField(labelWithString: "Version \(AgentVisionVersion.current)")
        versionLabel.frame = NSRect(x: 0, y: 178, width: 300, height: 18)
        versionLabel.alignment = .center
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        content.addSubview(versionLabel)

        // Author
        let authorLabel = NSTextField(labelWithString: "by Robin van Baalen")
        authorLabel.frame = NSRect(x: 0, y: 148, width: 300, height: 18)
        authorLabel.alignment = .center
        authorLabel.font = .systemFont(ofSize: 12)
        authorLabel.textColor = .secondaryLabelColor
        content.addSubview(authorLabel)

        // Website link
        let linkButton = NSButton(frame: NSRect(x: 50, y: 122, width: 200, height: 20))
        linkButton.title = "robinvanbaalen.nl/agent-vision"
        linkButton.bezelStyle = .inline
        linkButton.isBordered = false
        linkButton.font = .systemFont(ofSize: 12)
        linkButton.contentTintColor = .linkColor
        linkButton.target = self
        linkButton.action = #selector(openWebsite)
        content.addSubview(linkButton)

        // Separator
        let separator = NSBox(frame: NSRect(x: 20, y: 108, width: 260, height: 1))
        separator.boxType = .separator
        content.addSubview(separator)

        // Update status
        let updateStatus = NSTextField(labelWithString: "Checking for updates…")
        updateStatus.frame = NSRect(x: 0, y: 78, width: 300, height: 18)
        updateStatus.alignment = .center
        updateStatus.font = .systemFont(ofSize: 11)
        updateStatus.textColor = .secondaryLabelColor
        content.addSubview(updateStatus)
        self.updateLabel = updateStatus

        panel.contentView = content
        panel.makeKeyAndOrderFront(nil)
        self.window = panel

        triggerUpdateCheck()
    }

    func triggerUpdateCheck() {
        updateLabel?.stringValue = "Checking for updates…"
        updateLabel?.textColor = .secondaryLabelColor

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = self?.performUpdateCheck()
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .upToDate:
                    self.updateLabel?.stringValue = "✓ Up to date"
                    self.updateLabel?.textColor = .systemGreen
                case .updateAvailable(let version):
                    self.updateLabel?.stringValue = "Update available: v\(version)\nbrew upgrade agent-vision"
                    self.updateLabel?.textColor = .systemOrange
                    self.updateLabel?.maximumNumberOfLines = 2
                case .failed, .none:
                    self.updateLabel?.stringValue = "Could not check for updates"
                    self.updateLabel?.textColor = .secondaryLabelColor
                }
            }
        }
    }

    private enum UpdateResult {
        case upToDate
        case updateAvailable(String)
        case failed
    }

    private func performUpdateCheck() -> UpdateResult {
        let urlString = "https://api.github.com/repos/rvanbaalen/agent-vision/releases/latest"
        guard let url = URL(string: urlString) else { return .failed }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: UpdateResult = .failed

        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }

            let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let local = AgentVisionVersion.current

            if remote != local, remote > local {
                result = .updateAvailable(remote)
            } else {
                result = .upToDate
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 5)
        return result
    }

    @objc private func openWebsite() {
        if let url = URL(string: "https://robinvanbaalen.nl/agent-vision") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [ ] **Step 3: Wire up session menu rebuilds in AppDelegate**

In `Sources/agent-vision/AppDelegate.swift`, update the `sessionManager.onSessionsChanged` callback to also rebuild the menu. Change:

```swift
sessionManager.onSessionsChanged = { [weak self] in
    self?.toolbarWindow.refreshDropdown()
    self?.sessionManager.refreshBorderLabels()
}
```

to:

```swift
sessionManager.onSessionsChanged = { [weak self] in
    self?.toolbarWindow.refreshDropdown()
    self?.sessionManager.refreshBorderLabels()
    self?.rebuildSessionMenu()
}
```

- [ ] **Step 4: Build to verify everything compiles**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add Sources/agent-vision/MenuBarSetup.swift Sources/agent-vision/AboutWindow.swift Sources/agent-vision/AppDelegate.swift
git commit -m "feat: add menu bar (Agent Vision, Session, Help) and About window"
```

---

## Task 9: Update `SkillContent.swift` and `SKILL.md`

**Files:**
- Modify: `Sources/AgentVisionShared/SkillContent.swift`
- Modify: `SKILL.md`

- [ ] **Step 1: Update skill content**

In both `Sources/AgentVisionShared/SkillContent.swift` and `SKILL.md`:

1. Remove all references to the `wait` command
2. Update the Quick Start to show that `start` blocks and prints UUID + dimensions
3. Update the Session Management section to explain `start` blocks until area selected
4. Update the Full Example Session accordingly

Key changes to the "Session Management — READ THIS FIRST" section:

```
`agent-vision start` launches the GUI (or connects to an existing one), blocks until the user
selects a screen area, then prints the session UUID on the first line and the area dimensions
on the second line. It supports `--timeout N` (default 60s).
```

Quick Start update:

```bash
agent-vision start
# Blocks until user selects area, then prints:
# a1b2c3d4-e5f6-7890-abcd-ef1234567890
# Area selected: 800x600 at (100, 200)
# Use the UUID (first line) in all commands below:

agent-vision capture --session a1b2c3d4-...   # Take a screenshot
agent-vision elements --session a1b2c3d4-...  # Discover clickable elements
agent-vision control click --element 3 --session a1b2c3d4-...  # Click element #3
agent-vision stop --session a1b2c3d4-...      # End session
```

- [ ] **Step 2: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentVisionShared/SkillContent.swift SKILL.md
git commit -m "docs: update skill content for merged start+wait and multi-session"
```

---

## Task 10: Run full test suite and integration smoke test

**Files:** None — verification only

- [ ] **Step 1: Run all tests**

Run: `swift test 2>&1 | tail -30`
Expected: All tests pass (existing + new SessionColor tests + updated State tests)

- [ ] **Step 2: Build release**

Run: `swift build -c release 2>&1 | tail -5`
Expected: Build succeeds

- [ ] **Step 3: Smoke test — verify `start` spawns GUI and prints UUID**

Run: `timeout 5 .build/release/agent-vision start --timeout 3 2>&1 || true`
Expected: Should show timeout message (no area selected in 3s) but proves the command runs, spawns GUI, and polls.

- [ ] **Step 4: Verify `skill` command still works**

Run: `.build/release/agent-vision skill | head -5`
Expected: Shows updated skill content without `wait` references

- [ ] **Step 5: Verify help output**

Run: `.build/release/agent-vision --help`
Expected: Shows `start`, `capture`, `calibrate`, `preview`, `stop`, `control`, `elements`, `skill` — no `wait`

- [ ] **Step 6: Commit any fixes, then final commit**

```bash
git add -A
git commit -m "feat: multi-session GUI with colored borders, menu bar, and About window"
```
