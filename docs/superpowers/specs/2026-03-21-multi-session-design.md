# Multi-Session Support — Design Spec

## Problem

Only one Claude instance can use claude-vision at a time. Multiple Claude Code sessions can't control different windows simultaneously because they share one global state directory.

## Solution

UUID-based sessions. `claude-vision start` creates a session with a unique UUID. All subsequent commands require `--session <uuid>`. Each session has its own isolated state directory. No cross-session access.

### Session Lifecycle

```
claude-vision start                              → prints UUID to stdout
claude-vision wait --session <uuid>              → waits for area selection
claude-vision elements --session <uuid>          → scans elements
claude-vision control click --element 3 --session <uuid>
claude-vision stop --session <uuid>              → cleans up session dir
```

### File Layout

```
~/.claude-vision/sessions/<uuid>/
  state.json          # PID + capture area
  elements.json       # element scan cache
  action.json         # action request (CLI → GUI)
  action-result.json  # action result (GUI → CLI)
```

No shared files between sessions. The old global `~/.claude-vision/state.json` etc. are replaced entirely.

## Security / Isolation

- **UUID validation.** Session ID must match UUID format (`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`). Reject anything else before constructing paths.
- **No path traversal.** UUID validation prevents `../../etc` style attacks.
- **No session listing.** No command to enumerate sessions. Claude can only access the UUID it was given by `start`.
- **Bounds checking.** Existing `boundsError(for:)` still enforces that `--at` coordinates stay within the session's capture area. `--element` only targets elements within the area.
- **Cleanup on stop.** `stop --session <uuid>` deletes the entire session directory.
- **Stale cleanup.** `start` prunes session dirs older than 24h whose PIDs are dead.

## Changes

### Config.swift

Replace static global paths with a session-aware method:

```swift
public static func sessionDirectory(for sessionID: String) -> URL {
    stateDirectory.appendingPathComponent("sessions").appendingPathComponent(sessionID)
}

public static func stateFilePath(for sessionID: String) -> URL {
    sessionDirectory(for: sessionID).appendingPathComponent("state.json")
}

public static func elementsFilePath(for sessionID: String) -> URL {
    sessionDirectory(for: sessionID).appendingPathComponent("elements.json")
}

public static func actionFilePath(for sessionID: String) -> URL {
    sessionDirectory(for: sessionID).appendingPathComponent("action.json")
}

public static func actionResultFilePath(for sessionID: String) -> URL {
    sessionDirectory(for: sessionID).appendingPathComponent("action-result.json")
}
```

Keep old static paths for backward compatibility during transition, but they should not be used.

Add UUID validation:

```swift
public static func isValidSessionID(_ id: String) -> Bool {
    let pattern = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/
    return id.wholeMatch(of: pattern) != nil
}
```

### CLI.swift

**`start` command:**
- Generates a UUID via `UUID().uuidString.lowercased()`
- Creates the session directory
- Writes initial state (PID, no area) to `sessions/<uuid>/state.json`
- Launches the GUI app with the session UUID passed as an argument
- Prints the UUID to stdout

**All other commands** get `--session <uuid>` as a required option:
- Validate UUID format
- Derive paths from `Config.sessionDirectory(for:)`
- Everything else works the same, just with session-specific paths

**`stop` command:**
- Sends SIGTERM to the GUI process for this session
- Deletes the session directory

**Helper: `requireSession()`** — validates UUID, reads session state, checks PID alive, returns `(sessionID, area)`. Used by all commands.

### AppDelegate.swift / GUI App

The GUI app receives a session UUID as a launch argument.

**Single-session GUI process model:** Each `claude-vision start` launches a separate GUI process for that session. Each process manages one toolbar, one border, one action watcher — all scoped to its session's state files.

This is simpler than one GUI managing multiple sessions, and provides natural process-level isolation.

The GUI reads/writes to `sessions/<uuid>/` instead of the global paths. The session UUID is passed via:
- Command-line argument when launched directly: `claude-vision-app --session <uuid>`
- Or via `open -a "Claude Vision.app" --args --session <uuid>`

### ActionWatcher.swift

Accept session-specific paths in its initializer instead of using `Config.actionFilePath` / `Config.actionResultFilePath`:

```swift
init(actionPath: URL, resultPath: URL)
```

### ElementStore.swift

No changes — `read(from:)` and `write(_:to:createDirectory:)` already accept explicit paths.

### ElementAction.swift, ElementDiscovery.swift, TextDiscovery.swift

No changes — these don't touch state files.

## Stale Session Cleanup

On `start`, before creating a new session:
1. List dirs in `~/.claude-vision/sessions/`
2. For each, read `state.json` to get PID
3. If PID is dead AND dir is older than 24h, delete it
4. Don't delete active sessions or recently-created ones

## Edge Cases

- **GUI process dies unexpectedly**: Session dir remains. Cleaned up by stale cleanup on next `start`, or by `stop`.
- **Two `start` calls in quick succession**: Each gets a unique UUID. No collision.
- **Invalid UUID passed to any command**: Rejected immediately with "Invalid session ID" error.
- **Session dir doesn't exist**: "Session not found. Run 'claude-vision start' first."
- **Backward compatibility**: Old global state files are ignored. Users must use sessions.
