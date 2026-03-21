# Claude Vision Input Controls — Design Spec

Extend Claude Vision with input control actions (click, scroll, drag, type, key press) that execute within the selected area, enabling Claude to interact with on-screen UI.

## Problem

Claude can see the screen via `claude-vision capture` but cannot interact with it. To complete UI tasks autonomously — filling forms, clicking buttons, scrolling content — Claude needs input controls that are scoped to the selected area.

## CLI Interface

A new `control` subcommand with action sub-subcommands:

### `claude-vision control click --at X,Y`

Left-clicks at a position relative to the selected area's top-left corner.

- **Success**: `"Clicked at (150, 300)"`
- **Out of bounds**: `"Error: coordinates (500, 300) are outside the selected area (400x600)"` (exit code 1)
- **No area selected**: same error handling as `capture`

### `claude-vision control type --text "hello world"`

Types text at the current cursor position.

- **Success**: `"Typed \"hello world\""`
- Characters are typed sequentially with a brief delay between each

### `claude-vision control key --key KEY`

Presses a key or key combination.

- **Success**: `"Pressed enter"` / `"Pressed cmd+a"`
- Supports: `enter`, `tab`, `escape`, `space`, `delete`, `backspace`, `up`, `down`, `left`, `right`, `home`, `end`
- Modifiers: `cmd+`, `shift+`, `alt+`, `ctrl+` (can be combined: `cmd+shift+z`)
- Single characters: `--key a`, `--key 1`

### `claude-vision control scroll --delta DX,DY [--at X,Y]`

Scrolls by a pixel delta. Positive Y = scroll up, negative Y = scroll down.

- **Success**: `"Scrolled by (0, -100) at (200, 300)"`
- `--at` is optional; defaults to center of selected area
- `--at` position is bounds-checked

### `claude-vision control drag --from X,Y --to X,Y`

Click-and-drag from one point to another (for mobile simulator swipe gestures).

- **Success**: `"Dragged from (150, 400) to (150, 100)"`
- Both `--from` and `--to` are bounds-checked
- Interpolates mouse movement events along the path for smooth drag

## Safety: Bounds Checking

All coordinate inputs are validated against the selected area dimensions before execution:

- Coordinates must be within `(0, 0)` to `(area.width, area.height)`
- If any coordinate is out of bounds, the action is rejected with a clear error and exit code 1
- For drag: both `--from` and `--to` are validated
- For scroll with `--at`: the position is validated

The CLI converts relative coordinates to absolute screen coordinates by adding the area's origin: `absolute = relative + area.origin`. This conversion happens after bounds checking.

## Input Simulation

Uses macOS `CGEvent` API:

- **Click**: `CGEvent` with `.leftMouseDown` at position, then `.leftMouseUp`
- **Type**: For each character, creates a `CGEvent` keyboard event using `UniChar` mapping. Brief delay (10ms) between characters for reliability.
- **Key**: Maps key names to virtual key codes. Sets modifier flags (`.maskCommand`, `.maskShift`, `.maskAlternate`, `.maskControl`) on the event.
- **Scroll**: `CGEvent(scrollWheelEvent2:...)` with pixel delta values
- **Drag**: `.leftMouseDown` at start → series of `.leftMouseDragged` events interpolated along the path (10px steps) → `.leftMouseUp` at end

### Coordinate System

- User-facing coordinates: relative to selected area top-left, (0,0) = top-left
- CGEvent coordinates: absolute screen position, top-left origin (Quartz coordinates)
- Conversion: `screen_x = area.x + relative_x`, `screen_y = area.y + relative_y`
- Since the area coordinates in state.json are already in Quartz (top-left) coordinate system, no Y-flip is needed

### Permissions

Requires **Accessibility** permission (System Settings > Privacy & Security > Accessibility) in addition to Screen Recording. The CLI should detect missing permission and print: `"Error: Accessibility permission required. Enable it in System Settings > Privacy & Security > Accessibility for claude-vision-app."` (exit code 1)

## Visual Feedback

When an action executes, a brief visual indicator appears at the action point:

- **Click**: Blue circle (20px diameter) appears, scales up to 30px and fades out over 250ms
- **Type/Key**: Blue circle at the current action point (center of area if no click preceded it)
- **Scroll**: Small directional arrow indicator at the scroll position
- **Drag**: Circle at start point, animates along the drag path, fades at end point

### Feedback Window

- Separate NSWindow, same approach as BorderWindow
- `sharingType = .none` — excluded from screenshots
- `ignoresMouseEvents = true` — click-through
- Floating level, transparent background
- Dismissed automatically after animation completes

## IPC: Action Execution

The CLI cannot execute CGEvents directly (it's a command-line tool, not the GUI process with Accessibility permission). Actions flow through the GUI:

1. CLI writes action request to `~/.claude-vision/action.json`:
   ```json
   {
     "action": "click",
     "at": { "x": 150, "y": 300 },
     "timestamp": 1234567890
   }
   ```
2. GUI watches for `action.json` using a file watcher (DispatchSource)
3. GUI reads the action, validates it, executes the CGEvent
4. GUI shows visual feedback
5. GUI writes result to `~/.claude-vision/action-result.json`:
   ```json
   {
     "success": true,
     "message": "Clicked at (150, 300)",
     "timestamp": 1234567890
   }
   ```
6. GUI deletes `action.json`
7. CLI polls for `action-result.json`, reads it, prints the message, deletes it

### Action File Schemas

**Click:**
```json
{ "action": "click", "at": { "x": 150, "y": 300 } }
```

**Type:**
```json
{ "action": "type", "text": "hello world" }
```

**Key:**
```json
{ "action": "key", "key": "cmd+a" }
```

**Scroll:**
```json
{ "action": "scroll", "delta": { "dx": 0, "dy": -100 }, "at": { "x": 200, "y": 300 } }
```

**Drag:**
```json
{ "action": "drag", "from": { "x": 150, "y": 400 }, "to": { "x": 150, "y": 100 } }
```

**Result:**
```json
{ "success": true, "message": "Clicked at (150, 300)" }
```
or
```json
{ "success": false, "message": "Accessibility permission required..." }
```

### Timeout

CLI waits up to 5 seconds for action-result.json. If the GUI doesn't respond (crashed, hung), the CLI prints `"Error: action timed out — GUI may not be responding"` and exits with code 1.

## Project Structure Changes

```
Sources/
├── claude-vision/
│   └── CLI.swift                    # Add Control subcommand group
├── claude-vision-app/
│   ├── ActionWatcher.swift          # NEW: File watcher + CGEvent execution
│   ├── ActionFeedbackWindow.swift   # NEW: Visual ripple/animation overlay
│   └── AppDelegate.swift            # Wire up ActionWatcher
└── ClaudeVisionShared/
    ├── Action.swift                 # NEW: Codable action types + validation
    ├── KeyMapping.swift             # NEW: Key name → virtual key code mapping
    └── Config.swift                 # Add action file paths
```

## Error Handling

| Scenario | Error message | Exit code |
|----------|--------------|-----------|
| Coordinates out of bounds | `"Error: coordinates (X, Y) are outside the selected area (WxH)"` | 1 |
| No area selected | `"No area selected. Use 'claude-vision start' to launch and select an area."` | 1 |
| App not running | `"Claude Vision is not running. Use 'claude-vision start' first."` | 1 |
| Accessibility denied | `"Error: Accessibility permission required. Enable it in System Settings > Privacy & Security > Accessibility."` | 1 |
| Action timeout | `"Error: action timed out — GUI may not be responding"` | 1 |
| Invalid key name | `"Error: unknown key 'foo'. See 'claude-vision control key --help' for supported keys."` | 1 |

## Out of Scope

- Right click, double click (future update)
- Multi-touch gestures
- Screen recording / video
- OCR or element detection
