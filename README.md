# Claude Vision

A macOS utility that gives Claude Code eyes. Mark a region on your screen and Claude can take screenshots of it on demand — enabling visual feedback loops for UI development.

## Install

```bash
# Clone and build
git clone <repo-url> && cd claude-vision
swift build -c release

# Add to PATH (choose one)
ln -sf $(pwd)/.build/release/claude-vision ~/.local/bin/claude-vision
ln -sf $(pwd)/.build/release/claude-vision-app ~/.local/bin/claude-vision-app
```

Requires macOS 13+ and Screen Recording permission (macOS will prompt on first capture).

## Quick Start

```bash
claude-vision start          # Shows floating toolbar
# Click "Select Area" on the toolbar, drag to select a screen region
claude-vision wait           # Blocks until area is selected
claude-vision capture        # Prints path to screenshot PNG
claude-vision stop           # Quit
```

## CLI Reference

### `claude-vision start`

Launches the floating toolbar at the bottom center of your screen. The toolbar has two buttons: **Select Area** (drag to mark a capture region) and **Close** (quit).

```
$ claude-vision start
Claude Vision started. Use the toolbar to select an area.

$ claude-vision start  # already running
Claude Vision is already running (PID 12345)
```

### `claude-vision wait [--timeout N]`

Blocks until an area has been selected. Default timeout: 60 seconds.

```
$ claude-vision wait
Area selected: 800x600 at (100, 200)

$ claude-vision wait --timeout 10  # if no selection in time
No area selected within 10s
```

### `claude-vision capture [--output PATH]`

Captures the selected area and saves it as a PNG. Prints the absolute file path to stdout. If `--output` is not specified, saves to a temp file.

```
$ claude-vision capture
/var/folders/.../claude-vision-capture-1234567890.png

$ claude-vision capture --output ./screenshot.png
./screenshot.png
```

### `claude-vision stop`

Stops the app and cleans up. Idempotent — safe to call even if not running.

```
$ claude-vision stop
Claude Vision stopped.
```

## How It Works

- **Toolbar**: A floating macOS panel (like the built-in screenshot toolbar) that stays above all windows
- **Area selection**: Full-screen overlay with crosshair cursor — click and drag to select
- **Border**: A dashed blue border with "Claude Vision" label marks the active capture area. It's click-through (doesn't interfere with your content) and invisible to screenshots
- **State**: The app and CLI communicate via `~/.claude-vision/state.json` — the GUI writes the selected area coordinates, the CLI reads them to capture
- **Capture**: Uses `CGWindowListCreateImage` to screenshot the exact region. The border overlay is excluded automatically

## Re-selecting an Area

Click "Select Area" on the toolbar again at any time. The new selection replaces the old one. The border moves to the new area.

---

## Instructions for Claude

> **You can use `claude-vision` to see what's on screen.** This is your visual feedback loop for UI work.

### Setup: Start a Visual Feedback Session

At the beginning of a UI task, ask the user to set up a capture area:

```
I'd like to see the UI as I work on it. Can you do the following:
1. Run `claude-vision start` (I'll do this for you if you prefer)
2. Open the target UI in your browser/simulator
3. Click "Select Area" on the Claude Vision toolbar
4. Drag to select the area showing the UI

Then I can take screenshots as I make changes to verify my work visually.
```

Or start it yourself and ask the user to select:

```bash
claude-vision start
claude-vision wait --timeout 120  # Wait up to 2 minutes for the user to select
```

### Workflow: Visual Feedback Loop

Use this pattern when working on UI changes:

```
1. Take a "before" screenshot for reference
2. Make code changes
3. Wait for the UI to refresh (auto-refresh, hot reload, etc.)
4. Take an "after" screenshot
5. Compare and iterate
```

Example:

```bash
# 1. Capture current state as reference
claude-vision capture --output /tmp/before.png

# 2. Make your code changes...

# 3. Wait a moment for the UI to refresh
sleep 2

# 4. Capture the result
claude-vision capture --output /tmp/after.png

# 5. Read both screenshots to compare
# Use the Read tool on both PNGs to see them
```

### Workflow: Recreating a UI Element

When asked to recreate or match an existing design:

```bash
# Capture the reference design
claude-vision capture --output /tmp/reference.png
# Read it to understand the layout, colors, spacing, typography
# Then implement and capture your result to compare
```

### Workflow: Periodic Monitoring

For longer tasks, capture periodically to verify progress:

```bash
# After each significant change
claude-vision capture
# Read the resulting PNG to check your work
```

### Key Behaviors

- **Always capture before and after** when making visual changes — this lets you verify the change had the intended effect
- **Read the PNG** using the Read tool after capturing — the path printed by `capture` is what you pass to Read
- **Don't assume the UI updated** — if you don't see your change in the screenshot, the page may not have refreshed yet. Wait and capture again
- **The capture area stays fixed** — if the user scrolls or resizes the window, the capture area doesn't move with it. Ask the user to re-select if needed
- **Screenshots are just PNGs** — you can read them with the Read tool since Claude Code is multimodal

### Error Handling

If `capture` fails:

| Error | What to do |
|-------|-----------|
| `Claude Vision is not running` | Run `claude-vision start` and ask user to select an area |
| `No area selected` | Run `claude-vision wait` or ask user to click Select Area on the toolbar |
| `Screen capture failed — no image returned` | Screen Recording permission not granted — ask user to enable it in System Settings > Privacy & Security > Screen Recording |

### Example: Full UI Development Session

```bash
# Start Claude Vision
claude-vision start
# Ask user to select the browser area showing the UI

# Wait for selection
claude-vision wait

# Capture reference state
claude-vision capture --output /tmp/reference.png
# Read /tmp/reference.png to understand current UI

# Make code changes to the UI...

# Wait for hot reload
sleep 3

# Verify changes
claude-vision capture --output /tmp/result.png
# Read /tmp/result.png to check the changes

# If something looks wrong, iterate
# Make more changes, capture again, compare

# When done
claude-vision stop
```

## Development

```bash
swift build          # Debug build
swift build -c release  # Release build
swift test           # Run tests (11 tests)
```

### Project Structure

```
Sources/
├── claude-vision/           # CLI (ArgumentParser)
├── claude-vision-app/       # GUI (AppKit)
│   ├── AppDelegate.swift    # App lifecycle, state management
│   ├── ToolbarWindow.swift  # Floating toolbar panel
│   ├── SelectionOverlay.swift # Drag-to-select overlay
│   └── BorderWindow.swift   # Dashed border around area
└── ClaudeVisionShared/      # Shared library
    ├── State.swift          # State file IPC (JSON)
    ├── Config.swift         # Paths and constants
    └── Capture.swift        # CGWindowListCreateImage wrapper
```

## License

MIT
