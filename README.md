# Claude Vision

A macOS utility that gives Claude Code eyes. Mark a region on your screen and Claude can take screenshots of it on demand — enabling visual feedback loops for UI development.

## Install

```bash
git clone <repo-url> && cd claude-vision
./scripts/install.sh
```

This builds a release, installs **Claude Vision.app** to `/Applications`, and symlinks the `claude-vision` CLI to `~/.local/bin`.

You can then launch from Spotlight/Applications or use the CLI. Requires macOS 13+, Screen Recording permission, and Accessibility permission (for input controls).

## Quick Start

```bash
claude-vision start          # Shows floating toolbar
# Click "Select Area" on the toolbar, drag to select a screen region
claude-vision wait           # Blocks until area is selected
claude-vision capture        # Screenshot the area
claude-vision control click --at 100,50   # Click within the area
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

## How It Works

- **Toolbar**: A floating macOS panel (like the built-in screenshot toolbar) that stays above all windows
- **Area selection**: Full-screen overlay with crosshair cursor — click and drag to select
- **Border**: A dashed blue border with "Claude Vision" label marks the active capture area. It's click-through (doesn't interfere with your content) and invisible to screenshots
- **State**: The app and CLI communicate via `~/.claude-vision/state.json` — the GUI writes the selected area coordinates, the CLI reads them to capture
- **Capture**: Uses `CGWindowListCreateImage` to screenshot the exact region. The border overlay is excluded automatically
- **Input Controls**: Actions (click, scroll, type, etc.) are sent via JSON files to the GUI, which executes them using the macOS CGEvent API. A visual ripple appears at each action point. All coordinates are bounds-checked to stay within the selected area

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

### Key Behaviors

- **Always capture before and after** when making visual changes — this lets you verify the change had the intended effect
- **Read the PNG** using the Read tool after capturing — the path printed by `capture` is what you pass to Read
- **Don't assume the UI updated** — if you don't see your change in the screenshot, the page may not have refreshed yet. Wait and capture again
- **The capture area stays fixed** — if the user scrolls or resizes the window, the capture area doesn't move with it. Ask the user to re-select if needed
- **Screenshots are just PNGs** — you can read them with the Read tool since Claude Code is multimodal
- **Always describe what you see** — every time you analyze a screenshot, give the user a brief description of what's visible (layout, key elements, colors, state). This confirms you're looking at the right thing and builds shared understanding
- **Acknowledge UI issues honestly** — when the user points out a specific visual problem, look for it in the screenshot and describe what you see. If you can identify the issue, confirm it by describing the specifics. If you can't visually identify what the user is describing, say so honestly rather than guessing — ask for clarification or a new screenshot if needed

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
│   ├── BorderWindow.swift   # Dashed border around area
│   ├── ActionWatcher.swift  # File watcher + CGEvent execution
│   └── ActionFeedbackWindow.swift # Visual ripple overlay
└── ClaudeVisionShared/      # Shared library
    ├── State.swift          # State file IPC (JSON)
    ├── Config.swift         # Paths and constants
    ├── Capture.swift        # CGWindowListCreateImage wrapper
    ├── Action.swift         # Action types + file I/O
    └── KeyMapping.swift     # Key name → virtual key code
```

## License

MIT
