# Open Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `agent-vision open <application>` — launch/activate a macOS app and automatically select its window as a new session, without manual interaction.

**Architecture:** CLI launches the app via `/usr/bin/open -a`, creates a session with an `autoSelect` hint in `state.json`, and the GUI's `SessionManager` picks it up and programmatically matches the window via `CGWindowListCopyWindowInfo`. CLI polls for `area` as usual.

**Tech Stack:** Swift 6.0, Swift Argument Parser, CoreGraphics (`CGWindowListCopyWindowInfo`), Foundation (`Process`)

---

### Task 1: Add `AutoSelect` to `AppState`

**Files:**
- Modify: `Sources/AgentVisionShared/State.swift:41-62`

- [ ] **Step 1: Add the `AutoSelect` struct and field to `AppState`**

In `Sources/AgentVisionShared/State.swift`, add the `AutoSelect` struct before `AppState`, and add the `autoSelect` field to `AppState`:

```swift
public struct AutoSelect: Codable, Sendable {
    public let appName: String
    public let title: String?

    public init(appName: String, title: String? = nil) {
        self.appName = appName
        self.title = title
    }
}
```

Then update `AppState`:

```swift
public struct AppState: Codable, Sendable {
    public var pid: Int32
    public var area: CaptureArea?
    public var colorIndex: Int
    public var autoSelect: AutoSelect?

    public init(pid: Int32, area: CaptureArea?, colorIndex: Int = 0, autoSelect: AutoSelect? = nil) {
        self.pid = pid
        self.area = area
        self.colorIndex = colorIndex
        self.autoSelect = autoSelect
    }

    enum CodingKeys: String, CodingKey {
        case pid, area, colorIndex, autoSelect
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pid = try container.decode(Int32.self, forKey: .pid)
        area = try container.decodeIfPresent(CaptureArea.self, forKey: .area)
        colorIndex = try container.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        autoSelect = try container.decodeIfPresent(AutoSelect.self, forKey: .autoSelect)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentVisionShared/State.swift
git commit -m "feat: add AutoSelect struct to AppState for open command"
```

---

### Task 2: Add the `Open` CLI subcommand

**Files:**
- Modify: `Sources/agent-vision/CLI.swift:9-13` (subcommands list)
- Modify: `Sources/agent-vision/CLI.swift` (add new struct after `Start`)

- [ ] **Step 1: Add the `Open` struct**

In `Sources/agent-vision/CLI.swift`, add the `Open` command after the `Start` struct (after line 87):

```swift
struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open an application and start a session with its window auto-selected"
    )

    @Argument(help: "Application name (e.g. Safari, Finder, \"Visual Studio Code\")")
    var application: String

    @Option(name: .long, help: "Filter by window title (substring, case-insensitive)")
    var title: String?

    @Option(name: .long, help: "Timeout in seconds (default: 60)")
    var timeout: Int = 60

    func run() throws {
        checkForUpdate(owner: "rvanbaalen", repo: "agent-vision")
        Config.cleanStaleSessions()

        // Step 1: Launch or activate the application
        let openProcess = Process()
        openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProcess.arguments = ["-a", application]
        openProcess.standardOutput = FileHandle.nullDevice
        openProcess.standardError = FileHandle.nullDevice
        try openProcess.run()
        openProcess.waitUntilExit()

        if openProcess.terminationStatus != 0 {
            fputs("Failed to open \"\(application)\" — app not found or could not be launched.\n", stderr)
            throw ExitCode.failure
        }

        // Step 2: Create session with autoSelect hint
        let sessionID = UUID().uuidString.lowercased()
        let sessionDir = Config.sessionDirectory(for: sessionID)

        let existingColors = (try? existingSessionColorIndices()) ?? []
        let colorIndex = SessionColors.nextColorIndex(existing: existingColors)

        let guiPid = readGuiPid()
        let guiAlive = guiPid != nil && StateFile.isProcessRunning(pid: guiPid!)

        let autoSelect = AutoSelect(appName: application, title: title)
        let state = AppState(pid: guiPid ?? ProcessInfo.processInfo.processIdentifier, area: nil, colorIndex: colorIndex, autoSelect: autoSelect)
        try StateFile.write(state, to: Config.stateFilePath(for: sessionID), createDirectory: sessionDir)

        if !guiAlive {
            let pid = try spawnGUI()
            writeGuiPid(pid)
            let updatedState = AppState(pid: pid, area: nil, colorIndex: colorIndex, autoSelect: autoSelect)
            try StateFile.write(updatedState, to: Config.stateFilePath(for: sessionID), createDirectory: sessionDir)
        }

        // Step 3: Poll for area selection (GUI will auto-select the window)
        let statePath = Config.stateFilePath(for: sessionID)
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))

        fputs("Waiting for \"\(application)\" window to be detected...\n", stderr)

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

        fputs("No matching window found for \"\(application)\" within \(timeout)s\n", stderr)
        try? FileManager.default.removeItem(at: sessionDir)
        throw ExitCode.failure
    }
}
```

- [ ] **Step 2: Register `Open` in the subcommands list**

In `Sources/agent-vision/CLI.swift`, update the `subcommands` array on line 13:

Change:
```swift
subcommands: [Start.self, ListSessions.self, Focus.self, Capture.self, Calibrate.self, Preview.self, Stop.self, Control.self, Elements.self, Learn.self]
```
To:
```swift
subcommands: [Start.self, Open.self, ListSessions.self, Focus.self, Capture.self, Calibrate.self, Preview.self, Stop.self, Control.self, Elements.self, Learn.self]
```

- [ ] **Step 3: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/agent-vision/CLI.swift
git commit -m "feat: add 'open' CLI subcommand"
```

---

### Task 3: Add auto-select logic to `SessionManager`

**Files:**
- Modify: `Sources/agent-vision/SessionManager.swift:6-7` (add import)
- Modify: `Sources/agent-vision/SessionManager.swift:88-113` (adoptSession)
- Modify: `Sources/agent-vision/SessionManager.swift` (add new methods)

- [ ] **Step 1: Add auto-select timer and methods to `SessionManager`**

Add a `CoreGraphics` import at the top of `SessionManager.swift`:

```swift
import CoreGraphics
```

Add a property to `TrackedSession` to track auto-select state. Update the struct at line 7:

```swift
struct TrackedSession {
    let sessionID: String
    let colorIndex: Int
    var area: CaptureArea?
    var borderWindow: BorderWindow?
    var actionWatcher: ActionWatcher
    var autoSelect: AutoSelect?
    var autoSelectTimer: Timer?
}
```

In the `adoptSession` method, after the session is added to `sessions` (after line 109), add auto-select logic:

```swift
// Start auto-select polling if requested
if let autoSelect = state.autoSelect {
    sessions[id]?.autoSelect = autoSelect
    startAutoSelect(for: id, hint: autoSelect)
}
```

Add two new methods to `SessionManager`:

```swift
private func startAutoSelect(for sessionID: String, hint: AutoSelect) {
    NSLog("[agent-vision] SessionManager: starting auto-select for \(sessionID) (app=\(hint.appName))")
    let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
        Task { @MainActor in
            self?.tryAutoSelect(for: sessionID, hint: hint)
        }
    }
    sessions[sessionID]?.autoSelectTimer = timer
    // Also try immediately
    tryAutoSelect(for: sessionID, hint: hint)
}

private func tryAutoSelect(for sessionID: String, hint: AutoSelect) {
    guard sessions[sessionID] != nil, sessions[sessionID]?.area == nil else {
        // Already selected or session removed — stop polling
        sessions[sessionID]?.autoSelectTimer?.invalidate()
        sessions[sessionID]?.autoSelectTimer = nil
        return
    }

    guard let list = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]] else { return }

    let myPID = ProcessInfo.processInfo.processIdentifier

    for info in list {
        guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
              let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              let windowNum = info[kCGWindowNumber as String] as? UInt32,
              let ownerName = info[kCGWindowOwnerName as String] as? String,
              let wx = boundsDict["X"] as? CGFloat,
              let wy = boundsDict["Y"] as? CGFloat,
              let ww = boundsDict["Width"] as? CGFloat,
              let wh = boundsDict["Height"] as? CGFloat,
              ww > 50, wh > 50 else { continue }

        if pid == myPID { continue }
        if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 { continue }

        // Case-insensitive app name match
        guard ownerName.localizedCaseInsensitiveCompare(hint.appName) == .orderedSame else { continue }

        // Optional title filter
        if let titleFilter = hint.title {
            let windowTitle = info[kCGWindowName as String] as? String ?? ""
            guard windowTitle.localizedCaseInsensitiveContains(titleFilter) else { continue }
        }

        // Match found — create CaptureArea and write state
        let windowTitle = info[kCGWindowName as String] as? String
        let area = CaptureArea(
            x: Double(wx), y: Double(wy),
            width: Double(ww), height: Double(wh),
            windowNumber: windowNum,
            windowOwner: ownerName,
            windowTitle: windowTitle
        )

        NSLog("[agent-vision] SessionManager: auto-selected window \"\(ownerName)\" (\(windowNum)) for \(sessionID)")

        let tracked = sessions[sessionID]!
        let guiPid = ProcessInfo.processInfo.processIdentifier
        let state = AppState(pid: guiPid, area: area, colorIndex: tracked.colorIndex)
        do {
            try StateFile.write(state, to: Config.stateFilePath(for: sessionID), createDirectory: Config.sessionDirectory(for: sessionID))
        } catch {
            NSLog("[agent-vision] ERROR: Failed to write auto-selected area: \(error)")
        }

        // Stop polling
        sessions[sessionID]?.autoSelectTimer?.invalidate()
        sessions[sessionID]?.autoSelectTimer = nil
        // The scan() method will pick up the area change and create the border
        return
    }
}
```

- [ ] **Step 2: Clean up auto-select timer in `removeSession`**

In the `removeSession` method (around line 116), add timer cleanup before the existing cleanup:

```swift
sessions[id]?.autoSelectTimer?.invalidate()
sessions[id]?.autoSelectTimer = nil
```

Add it right before the existing `sessions[id]?.actionWatcher.stop()` line.

- [ ] **Step 3: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/agent-vision/SessionManager.swift
git commit -m "feat: add auto-select window matching to SessionManager"
```

---

### Task 4: Update `learn` command and SKILL.md

**Files:**
- Modify: `Sources/AgentVisionShared/SkillContent.swift`
- Modify: `SKILL.md`

- [ ] **Step 1: Update `SkillContent.swift`**

In `Sources/AgentVisionShared/SkillContent.swift`, add the `open` command documentation. There are three places to update:

**A) In the "How It Works" section** (around line 10), change step 1 from:

```
1. Run `agent-vision start` — it launches the GUI (or connects to an existing one) and blocks until the user selects a screen area
```

To:

```
1. Run `agent-vision open <app>` to open an application and auto-select its window, or `agent-vision start` for manual area selection — both block until the area is ready
```

**B) In the "Session Management — READ THIS FIRST" section**, add the `open` command as the preferred approach. After the existing paragraph about `start`, add:

```
**Preferred: Use `agent-vision open <app>` when you know which application to target.** It launches (or activates) the app and automatically selects its window — no manual interaction needed. Use `agent-vision start` only when you need manual area selection (e.g., selecting a sub-region or a custom area).

Step 1 — Open an application (blocks until window auto-selected):
\\```bash
agent-vision open Safari
\\```
Output:
\\```
a1b2c3d4-e5f6-7890-abcd-ef1234567890
Area selected: 1200x800 at (0, 38)
\\```
```

**C) In the "Command Reference > Session Management" section**, add after the `start` entry:

```
**`agent-vision open <application> [--title TITLE] [--timeout N]`**
Opens (or activates) an application by name and starts a session with its window automatically selected. No manual interaction required. Use `--title` to filter by window title substring (case-insensitive) when the app has multiple windows. Default timeout: 60s. Output format is the same as `start`.
```

**D) In the "Quick Start" section**, replace the existing example to lead with `open`:

```
\\```bash
agent-vision open Safari
# Blocks until Safari's window is auto-selected, then prints:
# a1b2c3d4-e5f6-7890-abcd-ef1234567890
# Area selected: 1200x800 at (0, 38)
# Use the UUID (first line) in all commands below:

agent-vision capture --session a1b2c3d4-...   # Take a screenshot (prints file path)
agent-vision elements --session a1b2c3d4-...  # Discover clickable elements (prints JSON)
agent-vision control click --element 3 --session a1b2c3d4-...  # Click element #3
agent-vision stop --session a1b2c3d4-...      # End session
\\```
```

- [ ] **Step 2: Mirror the same changes in `SKILL.md`**

Apply the same four changes (A, B, C, D) to `SKILL.md` at the repo root. The content should be identical to `SkillContent.swift` (minus the Swift string wrapper).

- [ ] **Step 3: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentVisionShared/SkillContent.swift SKILL.md
git commit -m "docs: add open command to learn output and SKILL.md"
```

---

### Task 5: Manual testing

- [ ] **Step 1: Build the project**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!`

- [ ] **Step 2: Test opening an app that's already running**

Run: `.build/debug/agent-vision open Safari`
Expected: Prints session UUID and area dimensions. Safari's window is auto-selected with a colored border.

- [ ] **Step 3: Test with `--title` filter**

Open multiple Safari windows with different titles. Run:
`.build/debug/agent-vision open Safari --title "GitHub"`
Expected: Selects the window whose title contains "GitHub".

- [ ] **Step 4: Test with an app that needs to be launched**

Quit Calculator, then run: `.build/debug/agent-vision open Calculator`
Expected: Calculator launches, then its window is auto-selected.

- [ ] **Step 5: Test with an invalid app name**

Run: `.build/debug/agent-vision open NonexistentApp123`
Expected: Immediate error: `Failed to open "NonexistentApp123" — app not found or could not be launched.`

- [ ] **Step 6: Test timeout with unmatched title filter**

Run: `.build/debug/agent-vision open Safari --title "NoSuchTitle12345" --timeout 5`
Expected: Waits 5 seconds, then errors: `No matching window found for "Safari" within 5s`

- [ ] **Step 7: Stop test sessions**

Clean up any sessions created during testing:
```bash
.build/debug/agent-vision list
.build/debug/agent-vision stop --session <uuid>
```

- [ ] **Step 8: Test the learn command**

Run: `.build/debug/agent-vision learn | head -30`
Expected: Output includes the `open` command in the "How It Works" and "Session Management" sections.
