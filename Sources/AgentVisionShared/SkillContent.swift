// Auto-generated skill content for `agent-vision skill` command.
// This is the canonical source — SKILL.md at the repo root is derived from this.

// swiftlint:disable line_length
public let skillContent: String = """
# Agent Vision — Instructions for AI Agents

Agent Vision is a macOS CLI tool that gives you eyes and hands on the user's screen. You can screenshot a selected region and control the mouse, keyboard, and UI elements within that region. Use it for visual feedback loops during UI development, navigating applications, filling forms, and any task that requires seeing and interacting with what's on screen.

## How It Works

1. Run `agent-vision open <app>` to open an application and auto-select its window, or `agent-vision start` for manual area selection — both block until the area is ready
2. On success, it prints the session UUID (first line) and area dimensions (second line)
3. You issue CLI commands with `--session <uuid>` to capture screenshots, discover elements, and control input
4. All interactions are scoped to the selected area — you cannot interact outside it

## Requirements

- macOS 14+ (Sonoma), Apple Silicon
- Screen Recording permission (System Settings > Privacy & Security > Screen Recording)
- Accessibility permission (System Settings > Privacy & Security > Accessibility)

## Session Management — READ THIS FIRST

**Preferred: Use `agent-vision open <app>` when you know which application to target.** It launches (or activates) the app and automatically selects its window — no manual interaction needed. Use `agent-vision start` only when you need manual area selection (e.g., selecting a sub-region or a custom area).

Both commands block until the area is ready, then print the session UUID on the first line and the area dimensions on the second line. They support `--timeout N` (default 60s). Every subsequent command requires `--session <uuid>` with this exact UUID.

**You must capture the UUID from the output and pass it as a literal string to every command.** Shell variables like `$SESSION` do not persist between separate command invocations.

Step 1 — Open an application (blocks until window auto-selected):
```bash
agent-vision open Safari
```
Output:
```
a1b2c3d4-e5f6-7890-abcd-ef1234567890
Area selected: 1200x800 at (0, 38)
```

Or, for manual area selection:
```bash
agent-vision start
```

Step 2 — Use that literal UUID in every subsequent command:
```bash
agent-vision capture --session a1b2c3d4-e5f6-7890-abcd-ef1234567890
agent-vision elements --session a1b2c3d4-e5f6-7890-abcd-ef1234567890
```

## Quick Start

```bash
agent-vision open Safari
# Blocks until Safari's window is auto-selected, then prints:
# a1b2c3d4-e5f6-7890-abcd-ef1234567890
# Area selected: 1200x800 at (0, 38)
# Use the UUID (first line) in all commands below:

agent-vision capture --session a1b2c3d4-...   # Take a screenshot (prints file path)
agent-vision elements --session a1b2c3d4-...  # Discover clickable elements (prints JSON)
agent-vision control click --element 3 --session a1b2c3d4-...  # Click element #3
agent-vision stop --session a1b2c3d4-...      # End session
```

## Command Reference

### Session Management

**`agent-vision open <application> [--title TITLE] [--timeout N]`**
Opens (or activates) an application by name and starts a session with its window automatically selected. No manual interaction required. Use `--title` to filter by window title substring (case-insensitive) when the app has multiple windows. Default timeout: 60s. Output format is the same as `start`. This is the preferred way to start a session when you know which app to target.

**`agent-vision start [--timeout N]`**
Creates a session and launches the GUI (or connects to an existing one). Blocks until the user manually selects an area. Default timeout: 60s. On success, prints session UUID (first line) and area dimensions (second line). The toolbar has three buttons: Select Area (drag to mark a region), Select Window (hover and click a window), Close. Use this when you need manual area selection or `open` doesn't apply.

**`agent-vision stop --session <uuid>`**
Stops the session and cleans up state.

**`agent-vision focus --session <uuid> [--timeout N]`**
Waits for the session window to have keyboard focus. Polls with exponential backoff (0.5s→8s). When focus is detected, waits 5 seconds and checks again to confirm it's stable. Fails after 20 attempts. Use this after a control command fails due to the window being out of focus.

**`agent-vision list`**
Lists active sessions with window owner, title, and dimensions.

### Screenshots

**`agent-vision capture --session <uuid> [--output PATH]`**
Captures the selected area as PNG. Prints absolute file path to stdout. Saves to temp file if --output not specified.

**`agent-vision calibrate --session <uuid> [--output PATH]`**
Captures with four crosshair markers at known coordinates. Fallback for when element discovery doesn't work — use the crosshairs as reference points to estimate coordinates.

**`agent-vision preview --session <uuid> --at X,Y [--output PATH]`**
Captures with a green crosshair drawn at X,Y without clicking. Use this to verify coordinates before executing a click.

### Element Discovery

**`agent-vision elements --session <uuid> [--annotated] [--output PATH]`**
Discovers interactive elements using the macOS Accessibility API and Vision OCR. Prints JSON to stdout with each element's index, role, label, center coordinates, and bounds.

The `--annotated` flag saves a screenshot with numbered badges on each element (blue = accessibility-sourced, orange = OCR-sourced). Screenshot path is printed to stderr.

Output format:
```json
{
  "area": { "x": 100, "y": 200, "width": 800, "height": 600 },
  "elementCount": 5,
  "elements": [
    { "index": 1, "source": "accessibility", "role": "button", "label": "Submit", "center": { "x": 400, "y": 150 }, "bounds": { "x": 350, "y": 130, "width": 100, "height": 40 } }
  ]
}
```

### Control Commands

**`agent-vision control click --session <uuid> [--element N | --at X,Y]`**
Left-click. Two targeting modes:
- `--element N` (preferred): Uses Accessibility API directly. Focus-free — does not move the cursor or steal focus from the user's active window.
- `--at X,Y` (fallback): Uses CGEvent. Moves cursor and steals focus. Only use when the element isn't in the scan.

**`agent-vision control type --session <uuid> --text TEXT [--element N]`**
Type text into a field.
- With `--element N`: Sets the field value directly via Accessibility API. Focus-free. Replaces the entire field value (does not append).
- Without `--element`: Types individual keystrokes at the current cursor position. Requires prior focus via click.

**`agent-vision control key --session <uuid> --key KEY`**
Press a key or combination.
- Named keys: `enter`, `tab`, `escape`, `space`, `delete`, `backspace`, `up`, `down`, `left`, `right`, `home`, `end`
- Modifiers: `cmd+`, `shift+`, `alt+`, `ctrl+` (combinable: `cmd+shift+a`)
- Single characters: a-z, 0-9

**`agent-vision control scroll --session <uuid> --delta DX,DY [--at X,Y]`**
Scroll by pixel delta. Negative Y = scroll down, positive Y = scroll up. Position defaults to center of area if --at not specified.

**`agent-vision control drag --session <uuid> --from X,Y --to X,Y`**
Click-and-drag between two points. Use for mobile simulator swipe gestures (touch interfaces don't respond to scroll events).

## Coordinate System

- All positions are relative to the **top-left** of the selected area
- `(0, 0)` = top-left corner; `(width-1, height-1)` = bottom-right corner
- Screenshot pixels map 1:1 to click coordinates — pixel position in the image = coordinate to pass
- All coordinates are bounds-checked; out-of-bounds actions are rejected with an error

## Core Pattern: Scan → Act → Re-scan

Every interaction follows this loop. Element indices become stale after any UI change — never reuse indices from a previous scan.

```bash
agent-vision elements --session <uuid>                        # 1. Scan
agent-vision control click --element 3 --session <uuid>       # 2. Act
sleep 0.5                                                      # 3. Wait for UI update
agent-vision elements --session <uuid>                        # 4. Re-scan (indices changed)
agent-vision control click --element 1 --session <uuid>       # 5. Act on NEW scan
```

## Window Focus

CGEvent control commands (`--at`, `type` without `--element`, `key`, `scroll`, `drag`) require the session window to have keyboard focus. **These commands auto-wait** — if the window doesn't have focus, the command blocks with exponential backoff until focus returns, then executes automatically. Default timeout: 120 seconds, overridable with `--focus-timeout N`.

If the window doesn't regain focus within the timeout, the command fails:
```
Error: Safari did not gain focus within 120s. Switch focus to it and retry.
```

**After a long focus wait, always capture before continuing.** The user may have changed the UI while the window was out of focus — buttons may have moved, text may have changed, the page may have navigated. Never assume the UI is in the same state as before.

`--element N` actions (via Accessibility API) are focus-free and work regardless of which window has focus. Prefer `--element` over `--at` whenever possible.

**`agent-vision focus --session <uuid> [--timeout N]`** is still available for explicit focus waiting (e.g., before a sequence of CGEvent actions), but is no longer required — control commands handle it automatically.

## Element Targeting Strategy

1. **Always run `elements` first.** Do not guess coordinates from screenshots.
2. **Use `--element N`** for anything interactive (buttons, links, fields). It's focus-free and more reliable.
3. **Use `--at X,Y` only as a last resort** — when the target genuinely isn't in the scan (canvas UIs, custom-drawn elements). This steals focus.
4. **OCR text vs interactive elements:** When you see OCR `staticText`, look for a nearby accessibility element (button, link, group) wrapping that text. Click the interactive parent with `--element`, not the OCR text with `--at`.
5. **Re-scan after every UI change.** After any click, navigation, form submission, or keystroke that changes the screen, run `elements` again before your next interaction.

## Workflows

### Visual Feedback Loop (UI Development)

```bash
agent-vision capture --session <uuid> --output /tmp/before.png  # Before
# ... make code changes ...
sleep 2  # Wait for hot reload
agent-vision capture --session <uuid> --output /tmp/after.png   # After
# Read both PNGs to compare
```

### Filling a Form

```bash
agent-vision elements --session <uuid>
# JSON shows: 1=textField "Name", 2=textField "Email", 3=button "Submit"
agent-vision control type --session <uuid> --text "John Doe" --element 1
agent-vision control type --session <uuid> --text "john@example.com" --element 2
agent-vision control click --session <uuid> --element 3
sleep 1
agent-vision capture --session <uuid>  # Verify result
```

Note: `type --element` replaces the field's entire value. To append, use `type --text` without `--element` (requires prior focus).

### Scrolling

Desktop apps — use scroll:
```bash
agent-vision control scroll --session <uuid> --delta 0,-300  # Down
agent-vision control scroll --session <uuid> --delta 0,300   # Up
```

Mobile emulators/simulators — use drag (touch interfaces need swipe gestures):
```bash
agent-vision control drag --session <uuid> --from 200,500 --to 200,200  # Scroll down
agent-vision control drag --session <uuid> --from 200,200 --to 200,500  # Scroll up
```

### Navigating Folders / Lists

```bash
agent-vision elements --session <uuid>
agent-vision control click --session <uuid> --element 5   # Open "Documents"
sleep 0.5
agent-vision elements --session <uuid>                    # Re-scan new contents
agent-vision control click --session <uuid> --element 3   # Open "Projects"
sleep 0.5
agent-vision elements --session <uuid>                    # Re-scan again
```

### Manual Coordinate Targeting (Fallback)

Only after confirming `elements` doesn't cover your target:
```bash
agent-vision preview --session <uuid> --at 400,150  # Verify position
# Read the preview image — green dot must be ON the target
agent-vision control click --session <uuid> --at 400,150  # Click
```

## Application-Specific Tips

| App Type | Key Behavior |
|----------|-------------|
| **Web browser** | Use address bar (Cmd+L) for navigation. Browser accessibility trees take ~2s to populate after page load. |
| **Mobile emulator** | Use `drag` instead of `scroll`. Touch interfaces don't respond to scroll wheel events. |
| **Email client** | Use the search bar to find emails. Rows have many overlapping interactive elements — always use `--element`. |
| **IDE / code editor** | Use Cmd+P for quick file navigation. |
| **Terminal** | Text-based — use `type` and `key` commands only. No clickable elements. |
| **Canvas / design tool** | Most elements won't appear in the scan. Must use `--at X,Y` with `preview` to verify. |
| **File manager** | Use path bar or search. Double-click folders to navigate. |

## Ground Rules

- **Only use agent-vision CLI commands** to interact with the UI. Do not use `open`, `osascript`, Puppeteer, Playwright, or any other tool.
- **Do not resize, move, or rearrange windows.** Work within the selected area as-is.
- **Stay inside the selected area.** If you need something outside it, ask the user to adjust.
- **Always describe what you see** after capturing a screenshot — this confirms you're looking at the right thing.
- **Verify focus before typing.** Never send keystrokes without confirming the target field is focused (capture and check for cursor/caret).
- **Verify outcomes through the UI**, not shell commands. After form submits, downloads, or navigation, capture and check visually.
- **Use the application's built-in features** — search bars, menus, keyboard shortcuts — instead of brute-force scrolling.

## Error Reference

| Error | What To Do |
|-------|-----------|
| `No element scan found` | Run `agent-vision elements` before using `--element` |
| `Element N not found` | Index out of range — re-run `elements` and check valid range |
| `Stale scan: capture area changed` | Area was reselected — re-run `elements` |
| `Specify either --at or --element, not both` | Use one targeting mode, not both |
| `coordinates are outside the selected area` | Check X,Y against the area dimensions from `start` output |
| `Accessibility permission required` | Ask user to grant Accessibility permission in System Settings |
| `Screen capture failed — no image returned` | Ask user to grant Screen Recording permission in System Settings |
| `action timed out` | GUI may not be responding — ask user to check if Agent Vision is still running |
| `Session is not running` | Run `agent-vision start` first |
| `No area selected` | Run `agent-vision start` — it blocks until an area is selected |
| `Invalid session ID` | The UUID format is wrong or missing — check you're passing the exact UUID from `start` output |
| `Session not found` | The session was stopped or expired — run `agent-vision start` again |
| `unknown key` | Check supported key names with `agent-vision control key --help` |

## Full Example Session

```bash
# Step 1: Open application — blocks until window is auto-selected
agent-vision open Safari
# Output:
# a1b2c3d4-e5f6-7890-abcd-ef1234567890
# Area selected: 1200x800 at (0, 38)
# Use the UUID (first line) in all commands below.

# Step 2: Capture reference state
agent-vision capture --session a1b2c3d4-e5f6-7890-abcd-ef1234567890 --output /tmp/reference.png
# Read /tmp/reference.png to understand current UI

# Step 3: Discover interactive elements
agent-vision elements --session a1b2c3d4-e5f6-7890-abcd-ef1234567890
# Read JSON — find target by label/role

# Step 4: Interact
agent-vision control click --session a1b2c3d4-e5f6-7890-abcd-ef1234567890 --element 2
agent-vision control type --session a1b2c3d4-e5f6-7890-abcd-ef1234567890 --text "hello" --element 2
agent-vision control click --session a1b2c3d4-e5f6-7890-abcd-ef1234567890 --element 5

# Step 5: Verify result
sleep 1
agent-vision capture --session a1b2c3d4-e5f6-7890-abcd-ef1234567890 --output /tmp/result.png
# Read /tmp/result.png to check outcome

# Step 6: End session
agent-vision stop --session a1b2c3d4-e5f6-7890-abcd-ef1234567890
```
"""
// swiftlint:enable line_length
