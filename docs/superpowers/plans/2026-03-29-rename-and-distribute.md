# Agent Vision: Rename + Homebrew Distribution Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename "Claude Vision" to "Agent Vision," merge CLI and GUI into one binary, and set up Homebrew distribution so users install with `brew install agent-vision`.

**Architecture:** Single Swift executable that switches between CLI mode (ArgumentParser subcommands) and GUI mode (`--gui` flag starts AppKit event loop). Distributed as a .app bundle built from source via Homebrew formula with ad-hoc codesign. No Apple Developer account needed.

**Tech Stack:** Swift 6.0, AppKit, CoreGraphics, Vision, ApplicationServices, swift-argument-parser, Homebrew

---

## File Structure

### Renamed (directory moves)
- `Sources/claude-vision/` -> `Sources/agent-vision/` (all CLI files)
- `Sources/claude-vision-app/` -> merged into `Sources/agent-vision/` (GUI files move here)
- `Sources/ClaudeVisionShared/` -> `Sources/AgentVisionShared/`
- `Tests/ClaudeVisionTests/` -> `Tests/AgentVisionTests/`

### Modified
- `Package.swift` — new target structure, one executable + one library
- `Sources/agent-vision/CLI.swift` — renamed struct, GUI mode flag, self-spawn logic
- `Sources/agent-vision/main.swift` — moved from claude-vision-app, integrated with CLI entry point
- `Sources/AgentVisionShared/Config.swift` — paths from `.claude-vision` to `.agent-vision`
- `Sources/agent-vision/ToolbarWindow.swift` — label text
- `Sources/agent-vision/BorderWindow.swift` — label text
- `Sources/agent-vision/AppDelegate.swift` — log prefixes, import
- `Sources/agent-vision/ActionWatcher.swift` — log prefixes, import, error messages
- All test files — import `AgentVisionShared`
- `README.md` — full rewrite of install and name references

### Created
- `Sources/AgentVisionShared/Version.swift` — version constant for update checks
- `Sources/agent-vision/UpdateCheck.swift` — GitHub release version check

### Deleted
- `scripts/install.sh` — replaced by Homebrew
- `Sources/claude-vision-app/` directory — merged into `Sources/agent-vision/`

---

### Task 1: Rename directories and Package.swift

**Files:**
- Modify: `Package.swift`
- Move: `Sources/claude-vision/` -> `Sources/agent-vision/`
- Move: `Sources/claude-vision-app/*.swift` -> `Sources/agent-vision/`
- Move: `Sources/ClaudeVisionShared/` -> `Sources/AgentVisionShared/`
- Move: `Tests/ClaudeVisionTests/` -> `Tests/AgentVisionTests/`

- [ ] **Step 1: Move source directories**

```bash
cd /Users/robin/Sites/projects/claude-vision
git mv Sources/claude-vision Sources/agent-vision
git mv Sources/ClaudeVisionShared Sources/AgentVisionShared
git mv Tests/ClaudeVisionTests Tests/AgentVisionTests
```

- [ ] **Step 2: Move GUI files into the CLI directory (binary merge prep)**

```bash
cd /Users/robin/Sites/projects/claude-vision
# Move all GUI files into agent-vision
git mv Sources/claude-vision-app/AppDelegate.swift Sources/agent-vision/
git mv Sources/claude-vision-app/ToolbarWindow.swift Sources/agent-vision/
git mv Sources/claude-vision-app/SelectionOverlay.swift Sources/agent-vision/
git mv Sources/claude-vision-app/BorderWindow.swift Sources/agent-vision/
git mv Sources/claude-vision-app/ActionWatcher.swift Sources/agent-vision/
git mv Sources/claude-vision-app/ActionFeedbackWindow.swift Sources/agent-vision/
git mv Sources/claude-vision-app/WindowSelectionOverlay.swift Sources/agent-vision/
# Keep main.swift for now — we'll merge it into CLI.swift in Task 3
git mv Sources/claude-vision-app/main.swift Sources/agent-vision/GUIMain.swift
# Remove the now-empty directory
rmdir Sources/claude-vision-app
```

- [ ] **Step 3: Update Package.swift**

Replace the entire file with:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "agent-vision",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "agent-vision",
            dependencies: [
                "AgentVisionShared",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "AgentVisionShared"
        ),
        .testTarget(
            name: "AgentVisionTests",
            dependencies: ["AgentVisionShared"]
        ),
    ]
)
```

Note: platform bumped from `.macOS(.v13)` to `.macOS(.v14)` per distribution design. The `claude-vision-app` target is removed — GUI code now lives in the single `agent-vision` target.

- [ ] **Step 4: Fix all import statements**

In every file under `Sources/agent-vision/` and `Tests/AgentVisionTests/`, replace:
```
import ClaudeVisionShared
```
with:
```
import AgentVisionShared
```

And in test files, replace:
```
@testable import ClaudeVisionShared
```
with:
```
@testable import AgentVisionShared
```

- [ ] **Step 5: Verify it compiles**

```bash
swift build 2>&1 | tail -20
```

Expected: Build will fail because `main.swift` and `@main` in CLI.swift conflict. That's expected — we fix this in Task 3. For now, just verify the package resolution and module naming works. If you see errors about "ClaudeVisionShared" not found, an import was missed.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: rename claude-vision to agent-vision (directory structure)"
```

---

### Task 2: Rename all string literals and identifiers

**Files:**
- Modify: `Sources/agent-vision/CLI.swift`
- Modify: `Sources/agent-vision/ToolbarWindow.swift`
- Modify: `Sources/agent-vision/BorderWindow.swift`
- Modify: `Sources/agent-vision/AppDelegate.swift`
- Modify: `Sources/agent-vision/GUIMain.swift`
- Modify: `Sources/agent-vision/ActionWatcher.swift`
- Modify: `Sources/AgentVisionShared/Config.swift`
- Modify: `Sources/AgentVisionShared/Capture.swift`
- Modify: `Sources/AgentVisionShared/ElementAction.swift`
- Modify: `Sources/AgentVisionShared/ElementDiscovery.swift`
- Modify: `Tests/AgentVisionTests/ClaudeVisionTests.swift`

- [ ] **Step 1: Rename Config.swift paths**

In `Sources/AgentVisionShared/Config.swift`, change line 5:
```swift
// Old:
        .appendingPathComponent(".claude-vision")
// New:
        .appendingPathComponent(".agent-vision")
```

- [ ] **Step 2: Rename CLI.swift identifiers and strings**

In `Sources/agent-vision/CLI.swift`:

1. Rename the struct (line 7-8):
```swift
// Old:
struct ClaudeVision: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "claude-vision",
        abstract: "Screen region capture tool for Claude Code",
// New:
struct AgentVision: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent-vision",
        abstract: "Give AI agents eyes on your screen",
```

2. Replace ALL occurrences of `"claude-vision` string literals with `"agent-vision` throughout the file. This covers:
   - Error messages: `"Session not found. Run 'claude-vision start' first."` -> `"Session not found. Run 'agent-vision start' first."`
   - `"Session is not running. Use 'claude-vision start' first."` -> `"Session is not running. Use 'agent-vision start' first."`
   - `"claude-vision elements"` -> `"agent-vision elements"`
   - `"claude-vision control click --at X,Y"` -> `"agent-vision control click --at X,Y"`
   - Temp file names: `"claude-vision-calibrate-"` -> `"agent-vision-calibrate-"`, `"claude-vision-preview-"` -> `"agent-vision-preview-"`, `"claude-vision-elements-"` -> `"agent-vision-elements-"`

3. Remove the `/Applications/Claude Vision.app` lookup block (lines 31-37) and the `"claude-vision-app"` sibling lookup (lines 39-58). Replace the entire GUI launch section with a placeholder comment `// GUI launch — replaced in Task 3`. We'll rewrite this in Task 3 when merging the binary.

- [ ] **Step 3: Rename GUI file strings**

In `Sources/agent-vision/ToolbarWindow.swift` line 51:
```swift
// Old:
let titleLabel = NSTextField(labelWithString: "Claude Vision")
// New:
let titleLabel = NSTextField(labelWithString: "Agent Vision")
```

In `Sources/agent-vision/BorderWindow.swift` lines 77-78:
```swift
// Old:
        let labelString = NSAttributedString(
            string: "Claude Vision",
// New:
        let labelString = NSAttributedString(
            string: "Agent Vision",
```

- [ ] **Step 4: Rename all NSLog prefixes**

In `Sources/agent-vision/GUIMain.swift`, `Sources/agent-vision/AppDelegate.swift`, and `Sources/agent-vision/ActionWatcher.swift`, replace every occurrence of `[claude-vision]` with `[agent-vision]`.

There are approximately 30+ NSLog calls across these files. Use find-and-replace:
- `"[claude-vision]"` -> `"[agent-vision]"`

Also in `GUIMain.swift` line 15:
```swift
// Old:
fputs("Usage: claude-vision-app --session <uuid>\n", stderr)
// New:
fputs("Usage: agent-vision --gui --session <uuid>\n", stderr)
```

- [ ] **Step 5: Rename remaining shared library references**

In `Sources/AgentVisionShared/Capture.swift`, find the temp filename:
```swift
// Old:
let filename = "claude-vision-capture-\(Int(Date().timeIntervalSince1970)).png"
// New:
let filename = "agent-vision-capture-\(Int(Date().timeIntervalSince1970)).png"
```

In `Sources/AgentVisionShared/ElementDiscovery.swift`, find the comment about skipping own windows:
```swift
// Old:
// Our own process ID — skip all windows belonging to Claude Vision
// New:
// Our own process ID — skip all windows belonging to Agent Vision
```

In `Sources/AgentVisionShared/ElementAction.swift`, find the error message:
```swift
// Old:
return "Element \(index) not found in current UI. Run 'claude-vision elements' again."
// New:
return "Element \(index) not found in current UI. Run 'agent-vision elements' again."
```

- [ ] **Step 6: Rename the test suite file and content**

Rename the file:
```bash
git mv Tests/AgentVisionTests/ClaudeVisionTests.swift Tests/AgentVisionTests/AgentVisionTests.swift
```

In that file, replace:
```swift
// Old:
@Suite struct ClaudeVisionTests {
// New:
@Suite struct AgentVisionTests {
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: rename all Claude Vision references to Agent Vision"
```

---

### Task 3: Merge CLI and GUI into one binary

**Files:**
- Modify: `Sources/agent-vision/CLI.swift`
- Delete: `Sources/agent-vision/GUIMain.swift` (logic merged into CLI.swift)

The single binary works like this:
- `agent-vision --gui --session <uuid>` -> starts AppKit event loop (GUI mode)
- `agent-vision start` -> spawns itself with `--gui` flag as a background process
- All other subcommands -> CLI mode, run and exit

- [ ] **Step 1: Add --gui flag to CLI entry point**

In `Sources/agent-vision/CLI.swift`, add a `--gui` option to the root command and modify the struct:

```swift
@main
struct AgentVision: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent-vision",
        abstract: "Give AI agents eyes on your screen",
        subcommands: [Start.self, Wait.self, Capture.self, Calibrate.self, Preview.self, Stop.self, Control.self, Elements.self]
    )

    @Flag(name: .long, help: .hidden)
    var gui: Bool = false

    @Option(name: .long, help: .hidden)
    var session: String?

    mutating func run() throws {
        if gui {
            guard let sid = session else {
                fputs("Usage: agent-vision --gui --session <uuid>\n", stderr)
                throw ExitCode.failure
            }
            startGUI(sessionID: sid)
            // startGUI never returns — it calls NSApp.run()
        }
        // If no subcommand and no --gui, show help
        throw CleanExit.helpRequest()
    }
}
```

- [ ] **Step 2: Add the startGUI function**

Add this function at the bottom of `CLI.swift` (or create a new file `Sources/agent-vision/GUIEntry.swift`). This replaces the logic from the old `main.swift` / `GUIMain.swift`:

```swift
import AppKit

func startGUI(sessionID: String) -> Never {
    NSLog("[agent-vision] App starting in GUI mode, session: \(sessionID)")

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

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    delegate.sessionID = sessionID
    app.delegate = delegate
    NSLog("[agent-vision] Running app loop")
    app.run()
    exit(0)  // NSApp.run() blocks forever; this is unreachable but satisfies Never
}
```

- [ ] **Step 3: Rewrite Start.run() to self-spawn**

In `Sources/agent-vision/CLI.swift`, replace the `Start` struct's `run()` method:

```swift
struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Launch the toolbar GUI and create a new session")

    func run() throws {
        Config.cleanStaleSessions()

        let sessionID = UUID().uuidString.lowercased()
        let sessionDir = Config.sessionDirectory(for: sessionID)

        let state = AppState(pid: ProcessInfo.processInfo.processIdentifier, area: nil)
        try StateFile.write(state, to: Config.stateFilePath(for: sessionID), createDirectory: sessionDir)

        // Spawn self in GUI mode as a background process
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        var size = UInt32(MAXPATHLEN)
        guard _NSGetExecutablePath(&pathBuffer, &size) == 0 else {
            throw ValidationError("Cannot determine executable path.")
        }
        let selfPath = String(cString: pathBuffer)
        let selfURL = URL(fileURLWithPath: selfPath).resolvingSymlinksInPath()

        let process = Process()
        process.executableURL = selfURL
        process.arguments = ["--gui", "--session", sessionID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        print(sessionID)
    }
}
```

- [ ] **Step 4: Delete GUIMain.swift**

```bash
git rm Sources/agent-vision/GUIMain.swift
```

- [ ] **Step 5: Build and verify**

```bash
swift build 2>&1 | tail -5
```

Expected: Build succeeds with one executable `agent-vision`.

```bash
.build/debug/agent-vision --help
```

Expected: Shows help with subcommands (start, wait, capture, etc.).

- [ ] **Step 6: Run tests**

```bash
swift test 2>&1 | tail -10
```

Expected: All existing tests pass. The tests only use `AgentVisionShared`, not the executable targets.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: merge CLI and GUI into single binary"
```

---

### Task 4: Add version constant and update check

**Files:**
- Create: `Sources/AgentVisionShared/Version.swift`
- Create: `Sources/agent-vision/UpdateCheck.swift`
- Modify: `Sources/agent-vision/CLI.swift` (call update check in Start)

- [ ] **Step 1: Create Version.swift**

Create `Sources/AgentVisionShared/Version.swift`:

```swift
public enum AgentVisionVersion {
    public static let current = "0.1.0"
}
```

- [ ] **Step 2: Create UpdateCheck.swift**

Create `Sources/agent-vision/UpdateCheck.swift`:

```swift
import Foundation
import AgentVisionShared

/// Non-blocking check for newer versions on GitHub.
/// Prints a one-line notice to stderr if a newer version exists.
/// Silently does nothing on any failure (network, parse, timeout).
func checkForUpdate(owner: String, repo: String) {
    let urlString = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
    guard let url = URL(string: urlString) else { return }

    var request = URLRequest(url: url)
    request.timeoutInterval = 2
    request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

    let semaphore = DispatchSemaphore(value: 0)
    var latestTag: String?

    let task = URLSession.shared.dataTask(with: request) { data, _, _ in
        defer { semaphore.signal() }
        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return }
        latestTag = tag
    }
    task.resume()

    // Wait max 2 seconds — never block startup longer than that
    _ = semaphore.wait(timeout: .now() + 2)

    guard let tag = latestTag else { return }

    // Strip leading "v" for comparison
    let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    let local = AgentVisionVersion.current

    if remote != local, remote > local {
        fputs("Update available: v\(local) → v\(remote). Run: brew upgrade agent-vision\n", stderr)
    }
}
```

- [ ] **Step 3: Call update check in Start.run()**

In `Sources/agent-vision/CLI.swift`, add the update check call at the very beginning of `Start.run()`, before `Config.cleanStaleSessions()`:

```swift
func run() throws {
    // Non-blocking update check (2s timeout, silent on failure)
    checkForUpdate(owner: "OWNER", repo: "agent-vision")

    Config.cleanStaleSessions()
    // ... rest of method unchanged
```

Replace `OWNER` with the actual GitHub username when the repo is created. For now, use a placeholder that's easy to find-and-replace later.

- [ ] **Step 4: Build and verify**

```bash
swift build 2>&1 | tail -5
```

Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentVisionShared/Version.swift Sources/agent-vision/UpdateCheck.swift Sources/agent-vision/CLI.swift
git commit -m "feat: add version constant and update check on start"
```

---

### Task 5: Update README and clean up

**Files:**
- Modify: `README.md`
- Delete: `scripts/install.sh`
- Delete: `examples/` (optional — keep if useful for docs)

- [ ] **Step 1: Delete install.sh**

```bash
git rm scripts/install.sh
rmdir scripts 2>/dev/null || true
```

- [ ] **Step 2: Update README.md**

Replace every occurrence of `claude-vision` with `agent-vision` and `Claude Vision` with `Agent Vision` throughout the README. Also update the install section:

At the top, replace the Install section with:

```markdown
## Install

```bash
brew tap OWNER/agent-vision
brew install agent-vision
```

Requires macOS 14+ (Sonoma), Apple Silicon, and Xcode 16+ (builds from source).

After install, grant permissions:
- **Screen Recording**: System Settings > Privacy & Security > Screen Recording
- **Accessibility**: System Settings > Privacy & Security > Accessibility
```

Replace the Development section build commands:
```markdown
## Development

```bash
swift build          # Debug build
swift build -c release  # Release build
swift test           # Run tests
```
```

Remove the reference to `./scripts/install.sh` and the "installs Claude Vision.app to /Applications" text.

- [ ] **Step 3: Update the CLAUDE.md instructions section**

In `README.md`, the "Instructions for Claude" section has many references to `claude-vision`. Replace all of them with `agent-vision`. This includes:
- All CLI example commands
- The `SESSION=$(claude-vision start)` pattern
- Error handling table entries
- Workflow examples

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs: update README for agent-vision rename and Homebrew install"
```

---

### Task 6: Final build and test verification

**Files:** None modified — verification only.

- [ ] **Step 1: Clean build**

```bash
rm -rf .build
swift build -c release 2>&1 | tail -5
```

Expected: Build succeeds. One binary at `.build/release/agent-vision`.

- [ ] **Step 2: Run all tests**

```bash
swift test 2>&1 | tail -20
```

Expected: All tests pass.

- [ ] **Step 3: Smoke test the binary**

```bash
.build/release/agent-vision --help
```

Expected: Shows "agent-vision" as command name, all subcommands listed.

```bash
.build/release/agent-vision --gui --session test 2>&1 | head -3
```

Expected: GUI attempts to start (may fail without display, that's OK — just verify it doesn't crash immediately with an import error).

- [ ] **Step 4: Verify no "claude" references remain in source**

```bash
grep -ri "claude" Sources/ Tests/ Package.swift --include="*.swift" | grep -v ".build/" | grep -v "Co-Authored-By"
```

Expected: Zero results. Every reference should be renamed.

- [ ] **Step 5: Commit any fixes**

If Step 4 found stragglers, fix them and commit:
```bash
git add -A
git commit -m "fix: remove remaining claude-vision references"
```

---

### Task 7: Create Homebrew tap repository

This task happens outside the main repo. It creates the Homebrew tap that users will use to install.

**Files:**
- Create: new repo `homebrew-agent-vision` on GitHub
- Create: `Formula/agent-vision.rb` in that repo

- [ ] **Step 1: Note for the developer**

This step requires creating a NEW GitHub repository called `homebrew-agent-vision` under your GitHub account. You also need to create a release tag on the main `agent-vision` repo first.

The formula file content (to be placed at `Formula/agent-vision.rb` in the tap repo):

```ruby
class AgentVision < Formula
  desc "Give AI agents eyes on your screen"
  homepage "https://github.com/OWNER/agent-vision"
  url "https://github.com/OWNER/agent-vision/releases/download/v0.1.0/agent-vision-arm64.tar.gz"
  sha256 "FILL_AFTER_RELEASE"
  license "MIT"

  depends_on :macos => :sonoma
  depends_on arch: :arm64

  def install
    app_bundle = prefix/"Agent Vision.app"
    (app_bundle).mkpath
    cp_r Dir["Agent Vision.app/*"], app_bundle

    bin.install_symlink app_bundle/"Contents/MacOS/agent-vision"
  end

  def caveats
    <<~EOS
      Agent Vision requires macOS permissions:
        - Screen Recording (System Settings > Privacy & Security > Screen Recording)
        - Accessibility (System Settings > Privacy & Security > Accessibility)
    EOS
  end

  test do
    assert_match "agent-vision", shell_output("#{bin}/agent-vision --help")
  end
end
```

- [ ] **Step 2: Create the GitHub repos and first release**

This is manual. Steps:
1. Create `agent-vision` repo on GitHub (rename or new)
2. Push the renamed code
3. Create tag `v0.1.0` and GitHub release
4. Download the release tarball, compute sha256: `curl -sL URL | shasum -a 256`
5. Create `homebrew-agent-vision` repo on GitHub
6. Add `Formula/agent-vision.rb` with the correct sha256
7. Test: `brew tap OWNER/agent-vision && brew install agent-vision`

- [ ] **Step 3: Verify the install works end-to-end**

```bash
brew tap OWNER/agent-vision
brew install agent-vision
agent-vision --help
```

Expected: Shows help. Binary is at `$(brew --prefix)/bin/agent-vision` (symlink into the .app bundle).

---

## Summary

| Task | What | Commits |
|------|------|---------|
| 1 | Directory renames + Package.swift | 1 |
| 2 | String literal renames everywhere | 1 |
| 3 | Merge CLI + GUI into one binary | 1 |
| 4 | Version constant + update check | 1 |
| 5 | README + cleanup | 1 |
| 6 | Final verification | 0-1 |
| 7 | Homebrew tap (separate repo) | external |

Total: ~5 commits in the main repo, 1 new repo for the Homebrew tap.
