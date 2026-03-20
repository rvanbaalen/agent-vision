# Claude Vision — Design Spec

A macOS utility that lets users mark a screen region and exposes a CLI for Claude Code to capture screenshots of that region.

## Problem

Claude Code cannot see what's on screen. When working on UI changes, it has no way to verify visual output. This tool bridges that gap by letting the user define a screen area and giving Claude a CLI to periodically screenshot it.

## Architecture

Two components sharing state via a file:

1. **CLI (`claude-vision`)** — single binary, subcommand-based entry point
2. **Toolbar GUI** — floating macOS window, launched by the CLI

### Tech Stack

- **Language:** Swift
- **GUI Framework:** AppKit
- **Screen Capture:** CGWindowListCreateImage
- **Build System:** Swift Package Manager

### IPC: State File

Located at `~/.claude-vision/state.json`:

```json
{
  "pid": 12345,
  "area": { "x": 100, "y": 200, "width": 800, "height": 600 }
}
```

- `start` launches the GUI process, which writes its PID
- GUI writes `area` when the user completes a selection
- `wait` polls the state file until `area` is present
- `capture` reads `area` and captures that screen region
- `stop` sends SIGTERM to the PID, removes the state file

## CLI Commands

### `claude-vision start`

Launches the toolbar GUI as a subprocess (detached).

- **Success:** `"Claude Vision started. Use the toolbar to select an area."`
- **Already running:** `"Claude Vision is already running (PID 12345)"`

### `claude-vision wait [--timeout 60]`

Blocks until an area is selected. Default timeout: 60 seconds.

- **Success:** `"Area selected: 800x600 at (100, 200)"`
- **Timeout:** `"No area selected within 60s"` (exit code 1)
- **Not running:** `"Claude Vision is not running. Use 'claude-vision start' first."` (exit code 1)

### `claude-vision capture [--output /path/to/file.png]`

Screenshots the selected area. Saves to a temp file if `--output` is not specified.

- **Success:** prints the absolute path to the PNG file (e.g., `/var/folders/.../claude-vision-capture-1234.png`)
- **No area:** `"No area selected. Use 'claude-vision start' to launch and select an area."` (exit code 1)
- **Not running:** `"Claude Vision is not running. Use 'claude-vision start' first."` (exit code 1)

### `claude-vision stop`

Stops the GUI process and cleans up state.

- **Success:** `"Claude Vision stopped."`
- **Not running:** `"Claude Vision is not running."` (exit code 0 — idempotent)

## UI Design

### Floating Toolbar

- Positioned at **bottom center** of the main screen
- Dark translucent background (`NSVisualEffectView`) with rounded corners
- Matches macOS screenshot toolbar aesthetic
- Float level: `NSWindow.Level.floating`
- Two controls:
  - **Close button (✕)** — quits the app, cleans up state file
  - **Select Area button** — enters area selection mode
- Hides during area selection to avoid being captured

### Area Selection Mode

- Full-screen transparent overlay window with slight dim (30% black)
- Crosshair cursor
- Click + drag draws a blue rectangle (`#007AFF`)
- Dimensions label shown while dragging (e.g., "280 × 160")
- Mouse release confirms the selection
- **Escape** cancels and returns to toolbar

### Active Area Border

- Thin dashed blue border (`#007AFF`, 2px) around the selected region
- Small "Claude Vision" label in the top-right corner of the border
- **Click-through** — `ignoresMouseEvents = true` so it doesn't interfere with content underneath
- **Excluded from captures** — the border window is not included in `CGWindowListCreateImage` calls

## Screen Capture

Uses `CGWindowListCreateImage` with:
- `CGRect` matching the selected area coordinates
- `CGWindowListOption.optionOnScreenOnly` to capture everything visible in the region
- The border overlay window uses `NSWindow.Level` and `sharingType = .none` so it is automatically excluded from screen captures
- Saves as PNG to temp directory (or user-specified path)

**Note:** `capture` requires the GUI to be running (live PID check). This ensures the border overlay is active and the state is current. A stale state file with no running GUI is treated as "not running."

## State Management

### State File Location

`~/.claude-vision/state.json`

### Lifecycle

1. `claude-vision start` → creates `~/.claude-vision/` dir, launches GUI, GUI writes `{ "pid": <pid> }`
2. User selects area → GUI updates state to `{ "pid": <pid>, "area": { ... } }`
3. User re-selects area → GUI overwrites `area` with new coordinates
4. `claude-vision stop` → sends SIGTERM, removes state file
5. GUI quit (via close button) → GUI removes state file on exit

### Process Detection

The CLI checks if the app is running by:
1. Reading `pid` from state file
2. Checking if that PID is still alive (`kill(pid, 0)`)
3. If the PID is dead, cleans up stale state file

## Project Structure

```
claude-vision/
├── Package.swift
├── Sources/
│   ├── ClaudeVisionCLI/       # CLI entry point
│   │   └── main.swift
│   ├── ClaudeVisionApp/       # GUI toolbar app
│   │   ├── AppDelegate.swift
│   │   ├── ToolbarWindow.swift
│   │   ├── SelectionOverlay.swift
│   │   └── BorderWindow.swift
│   └── ClaudeVisionShared/    # Shared types & state management
│       ├── State.swift
│       └── Config.swift
├── docs/
│   └── superpowers/
│       └── specs/
│           └── 2026-03-20-claude-vision-design.md
└── .gitignore
```

## Error Handling

- All CLI errors print to stderr and exit with code 1
- All success output prints to stdout
- GUI crashes clean up state file via signal handler
- Stale PID detection prevents zombie state

## Security & Permissions

- Requires **Screen Recording** permission (macOS will prompt on first capture)
- No network access
- State file is user-readable only (0600)

## Out of Scope

- Multiple simultaneous areas
- Cross-session persistence
- Auto-refresh or polling (Claude decides when to capture)
- Video recording
- Integration with specific IDEs or browsers
