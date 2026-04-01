# Open Command Design

## Overview

Add `agent-vision open <application>` — a command that launches (or activates) a macOS application by name, starts a session, and automatically selects the app's window without manual interaction. This gives AI agents a single command to go from "I want to work with Safari" to a ready-to-use session.

## CLI Interface

```
agent-vision open <application> [--title <string>] [--timeout <seconds>]
```

- `application` — required positional argument. The app name (e.g., `Safari`, `Finder`, `Visual Studio Code`).
- `--title` — optional. Filter by window title substring, case-insensitive. Useful when the app has multiple windows.
- `--timeout` — optional, default 60s. How long to wait for app launch and window selection.

**Output** (same format as `start`):

```
<session-uuid>
<width>x<height>
```

**Error cases:**

- App not found or failed to launch: exit immediately with error message.
- No matching window found within timeout: exit with error message.
- Title filter matched no windows within timeout: exit with error message.

## Architecture

Uses the existing file-based IPC pattern: CLI writes intent to the filesystem, GUI acts on it, CLI polls for the result.

### Step 1: CLI launches the app

The CLI runs `/usr/bin/open -a "<application>"` via `Process`. This activates the app if already running or launches it if not. If `open -a` exits with a non-zero code (app not found), the CLI exits immediately with an error. The CLI does not wait for the app to fully launch — the GUI's auto-select polling handles that.

### Step 2: CLI creates session with auto-select hint

The CLI creates the session directory and writes `state.json` with a new optional `autoSelect` field:

```json
{
  "pid": 12345,
  "area": null,
  "colorIndex": 2,
  "autoSelect": {
    "appName": "Safari",
    "title": "GitHub"
  }
}
```

- `autoSelect.appName` — always present, matches the `application` argument.
- `autoSelect.title` — only present if `--title` was passed.

### Step 3: GUI auto-selects the window

When `SessionManager` discovers a new session with `autoSelect` set, it runs a window-matching loop at 500ms intervals:

1. Scan `CGWindowListCopyWindowInfo` for a window where:
   - `kCGWindowOwnerName` matches `appName` (case-insensitive)
   - If `title` is set, `kCGWindowName` contains the title substring (case-insensitive)
   - Window is on-screen and has nonzero size
2. Pick the frontmost matching window (by window list order).
3. If found: create a `CaptureArea` from the window bounds, write to `state.json` — same path as manual window selection.
4. If not found: retry on the next 500ms poll cycle. The app may still be launching.

### Step 4: CLI polls for completion

Same polling loop as `start` — wait for `area` to be populated in `state.json`, subject to `--timeout`.

## State File Changes

Add to `AppState`:

```swift
struct AutoSelect: Codable {
    let appName: String
    let title: String?
}
```

Add optional `autoSelect: AutoSelect?` field to `AppState`. The field is written by the CLI and read by the GUI. Once the GUI selects the window, it can clear `autoSelect`.

## Files Changed

| File | Change |
|------|--------|
| `Sources/AgentVisionShared/State.swift` | Add `AutoSelect` struct and optional `autoSelect` field to `AppState` |
| `Sources/agent-vision/CLI.swift` | Add `Open` subcommand, register in subcommands list, update `Learn` output |
| `Sources/agent-vision/SessionManager.swift` | Detect `autoSelect` on new sessions, run 500ms auto-select polling with CGWindowList scan |

## Learn Command Update

The `learn` command output must document the `open` command so AI agents know:

- `agent-vision open <app>` is the preferred way to start a session when the target app is known.
- `--title` is available for filtering multi-window apps.
- Output format is the same as `start` (UUID + dimensions).
- After `open`, the agent proceeds to `capture`, `elements`, etc. (or `focus` first if CGEvent actions are needed).
- `start` is reserved for manual area selection when `open` doesn't apply.

## Testing

Manual testing:

- `agent-vision open Safari` — verify session created, correct window selected
- `agent-vision open Safari --title "GitHub"` — verify title filtering
- `agent-vision open Safari` when Safari is already running — verify it activates and selects
- `agent-vision open NonexistentApp` — verify immediate error
- `agent-vision open Safari --title "NoSuchTitle" --timeout 5` — verify timeout error
- Multiple windows open — verify frontmost is selected without `--title`
