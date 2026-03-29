# Agent Vision

A macOS utility that gives AI agents eyes on your screen. Mark a region on your screen and any AI coding agent can take screenshots of it on demand — enabling visual feedback loops for UI development.

## Install

```bash
brew tap OWNER/agent-vision
brew install agent-vision
```

Requires macOS 14+ (Sonoma), Apple Silicon, and Xcode 16+ (builds from source).

After install, grant permissions:
- **Screen Recording**: System Settings > Privacy & Security > Screen Recording
- **Accessibility**: System Settings > Privacy & Security > Accessibility

## Quick Start

```bash
agent-vision start          # Prints session UUID, shows floating toolbar
# Click "Select Window" to pick a window, or "Select Area" to drag-select a region
agent-vision wait --session <uuid>           # Blocks until area is selected
agent-vision elements --session <uuid>       # Discover clickable elements
agent-vision control click --element 1 --session <uuid>   # Click (focus-free)
agent-vision stop --session <uuid>           # End session
```

Every command (except `start`) requires `--session <uuid>`. Multiple agent instances can run separate sessions simultaneously without interfering.

## CLI Reference

### `agent-vision start`

Creates a new session and launches the floating toolbar. Prints the session UUID to stdout. The toolbar has three buttons: **Select Area** (drag to mark a capture region), **Select Window** (hover and click a window to select it), and **Close** (quit).

```
$ agent-vision start
a1b2c3d4-e5f6-7890-abcd-ef1234567890
```

All subsequent commands require `--session <uuid>`.

### `agent-vision wait --session <uuid> [--timeout N]`

Blocks until an area has been selected. Default timeout: 60 seconds.

```
$ agent-vision wait --session $SESSION
Area selected: 800x600 at (100, 200)

$ agent-vision wait --session $SESSION --timeout 10
No area selected within 10s
```

### `agent-vision capture --session <uuid> [--output PATH]`

Captures the selected area and saves it as a PNG. Prints the absolute file path to stdout. If `--output` is not specified, saves to a temp file.

```
$ agent-vision capture --session $SESSION
/var/folders/.../agent-vision-capture-1234567890.png

$ agent-vision capture --session $SESSION --output ./screenshot.png
./screenshot.png
```

### `agent-vision calibrate --session <uuid> [--output PATH]`

Captures the selected area with four crosshair markers at known coordinates overlaid on the image. Fallback for when element discovery doesn't work.

```
$ agent-vision calibrate --session $SESSION
/var/folders/.../agent-vision-calibrate-1234567890.png
Crosshairs at: (200,150) (600,150) (200,450) (600,450)
```

### `agent-vision preview --session <uuid> --at X,Y [--output PATH]`

Captures the selected area with a green crosshair drawn at the specified position — without actually clicking. Use this to verify click coordinates before executing a control command.

```
$ agent-vision preview --session $SESSION --at 200,150
/var/folders/.../agent-vision-preview-1234567890.png
```

### `agent-vision stop --session <uuid>`

Stops the session and cleans up its state directory.

```
$ agent-vision stop --session $SESSION
Session stopped.
```

### `agent-vision elements --session <uuid> [--annotated] [--output PATH]`

Discovers interactive elements in the selected area using the macOS Accessibility API and Vision OCR. Prints a JSON list of elements to stdout, each with an index, role, label, and exact coordinates. Use this instead of guessing coordinates from screenshots.

```
$ agent-vision elements --session $SESSION
{
  "area": { "x": 100, "y": 200, "width": 800, "height": 600 },
  "elementCount": 5,
  "elements": [
    { "index": 1, "source": "accessibility", "role": "button", "label": "Submit", "center": { "x": 400, "y": 150 }, "bounds": { ... } },
    { "index": 2, "source": "accessibility", "role": "textField", "label": "Email", "center": { "x": 400, "y": 100 }, "bounds": { ... } },
    ...
  ]
}

$ agent-vision elements --session $SESSION --annotated
# Same JSON output + saves annotated screenshot with numbered badges on each element
# Screenshot path printed to stderr
```

The `--annotated` flag saves a screenshot with numbered badges overlaid on each element (blue for accessibility-sourced, orange for OCR-sourced). Useful when you need spatial context.

### `agent-vision control click --session <uuid> --at X,Y` or `--element N`

Left-clicks at a position. Two targeting modes:

```
# By element index (preferred — focus-free, uses AX API directly)
$ agent-vision control click --session $SESSION --element 1
Clicked Submit (focus-free)

# By manual coordinates (fallback — uses CGEvent, steals focus)
$ agent-vision control click --session $SESSION --at 150,300
Clicked at (150, 300)
```

`--element N` uses the macOS Accessibility API to press the element directly — **it does not move the cursor or steal focus**. You can keep working while the agent interacts with the UI. `--at X,Y` falls back to CGEvent which does move the cursor.

### `agent-vision control type --session <uuid> --text TEXT [--element N]`

Types text. Two modes:

```
# Focus-free: set text directly on a field by element index (replaces field value)
$ agent-vision control type --session $SESSION --text "hello world" --element 2
Typed into Email (focus-free)

# Legacy: type keystrokes at current cursor position (requires prior focus, steals focus)
$ agent-vision control type --session $SESSION --text "hello world"
Typed "hello world"
```

With `--element N`, the text is set directly via the Accessibility API — no cursor movement, no focus steal. Note: this **replaces** the field's entire value rather than appending.

### `agent-vision control key --session <uuid> --key KEY`

Presses a key or key combination. Supports: `enter`, `tab`, `escape`, `space`, `delete`, `backspace`, `up`, `down`, `left`, `right`, `home`, `end`. Modifiers: `cmd+`, `shift+`, `alt+`, `ctrl+`.

```
$ agent-vision control key --session $SESSION --key enter
Pressed enter

$ agent-vision control key --session $SESSION --key "cmd+a"
Pressed cmd+a
```

### `agent-vision control scroll --session <uuid> --delta DX,DY [--at X,Y]`

Scrolls by pixel delta. Negative Y = scroll down, positive Y = scroll up. Position defaults to center of area.

```
$ agent-vision control scroll --session $SESSION --delta 0,-100
Scrolled by (0, -100) at (200, 300)
```

### `agent-vision control drag --session <uuid> --from X,Y --to X,Y`

Click-and-drag between two points. Useful for mobile simulator swipe gestures.

```
$ agent-vision control drag --session $SESSION --from 150,400 --to 150,100
Dragged from (150, 400) to (150, 100)
```

## How It Works

- **Toolbar**: A floating macOS panel (like the built-in screenshot toolbar) that stays above all windows
- **Area selection**: Full-screen overlay with crosshair cursor — click and drag to select
- **Border**: A dashed blue border with "Agent Vision" label marks the active capture area. It's click-through (doesn't interfere with your content) and invisible to screenshots
- **State**: The app and CLI communicate via `~/.agent-vision/state.json` — the GUI writes the selected area coordinates, the CLI reads them to capture
- **Capture**: Uses `CGWindowListCreateImage` to screenshot the exact region. The border overlay is excluded automatically
- **Input Controls**: Actions (click, scroll, type, etc.) are sent via JSON files to the GUI, which executes them using the macOS CGEvent API. A visual ripple appears at each action point. All coordinates are bounds-checked to stay within the selected area

## Re-selecting an Area

Click "Select Area" on the toolbar again at any time. The new selection replaces the old one. The border moves to the new area.

---

## Instructions for AI Agents

> **You can use `agent-vision` to see what's on screen.** This is your visual feedback loop for UI work.

### Ground Rules

**When instructed to use Agent Vision, achieve your goal ONLY through the `agent-vision` CLI.** Do not use any other tools, commands, or workarounds — even if they seem faster or easier:

- **Do NOT** use `open`, `osascript`, `xdg-open`, AppleScript, or any other command to open URLs, launch apps, or create new windows. Navigate within the selected window using clicks and keyboard input.
- **Do NOT** use browser automation tools (Puppeteer, Playwright, Selenium). You have a real screen — use it.
- **Do NOT** resize, move, or rearrange windows. Work within the selected area as-is.
- **Do NOT** use system-wide searches (`find`, `mdfind`, `spotlight`), file system commands, or other CLI tools to accomplish the task. If the user says "use agent-vision to find X" or "use agent-vision to open Y", that means navigate to it visually — through the UI, using clicks, keyboard input, and element discovery. The only exception is if the user explicitly asks you to use another tool.
- **Stay inside the selected area.** All your interactions must happen within the capture area the user selected. If you need something outside it, ask the user to adjust.
- **One window, one area.** The capture area targets a specific window. All navigation (clicking links, pressing back, switching tabs) happens through `agent-vision control` commands within that window.

### Understand the Interface First

**Before interacting with any application, take a screenshot and identify what kind of interface you're working with.** Different application types have different conventions, navigation patterns, and capabilities. Adapt your approach accordingly.

After your first capture, determine the application type and note its implications:

| Application type | Key behaviors |
|-----------------|---------------|
| **Email client** (Mail, Outlook, Gmail) | Has search, mailbox sidebar, message list, preview pane. Use search to find specific emails. Look for attachment icons (paperclip) on messages. Double-click to open in separate window if needed. |
| **Web browser** (Chrome, Safari, Firefox, Arc) | Has address bar, tabs, back/forward. Use the address bar to navigate. Look for tab titles. Browser DevTools may be open — don't confuse them with page content. |
| **Mobile emulator/simulator** (iOS Simulator, Android Emulator, Expo) | Use `drag` instead of `scroll` — touch interfaces respond to swipe gestures, not scroll wheel events. Buttons may look different from native desktop buttons. |
| **File manager** (Finder, file dialogs) | Has sidebar, path bar, file list. Navigation happens by double-clicking folders. Use column/list view affordances. Look for breadcrumbs or path bar for orientation. |
| **IDE / code editor** (VS Code, Xcode, IntelliJ) | Has sidebar, editor tabs, terminal panel, status bar. Use Cmd+P / Cmd+Shift+P for quick navigation. Look for file tree in sidebar. |
| **Terminal** | Text-based — no buttons or links to click. Use `type` and `key` commands. Wait for command output before typing next command. |
| **Form / settings UI** | Has labeled fields, dropdowns, toggles, save buttons. Use `elements` to find fields by label. Fill fields with `type --element N`. |
| **Canvas / design tool** (Figma, Sketch) | Most elements won't appear in accessibility scan. Use `--at X,Y` coordinates. Zoom level affects coordinate mapping. |

**Use the application's built-in features.** Every application has navigation tools — search bars, sidebars, menus, keyboard shortcuts. Use them instead of brute-force scrolling or guessing. For example:
- In a **mail client**: use the search bar to find emails by sender, subject, or content — don't scroll through hundreds of messages
- In a **browser**: use the address bar or Cmd+L to navigate — don't hunt for links
- In a **file manager**: use the path bar or search — don't click through folder after folder
- In any app: look for **menus** (File, Edit, View) — they often have the action you need

**Identify attachments, downloads, and embedded content.** When looking for files within an application (email attachments, downloads, embedded documents), look for visual indicators specific to that app type — paperclip icons, "Attachments:" headers, download bars, or preview thumbnails. Don't assume content is only available via external links.

### Setup: Start a Visual Feedback Session

At the beginning of a UI task, ask the user to set up a capture area:

```
I'd like to see the UI as I work on it. Can you do the following:
1. Run `agent-vision start` (I'll do this for you if you prefer)
2. Open the target UI in your browser/simulator
3. Click "Select Window" to select the entire window, or "Select Area" to drag-select a region
4. For "Select Window": hover over the target window and click it

Then I can take screenshots as I make changes to verify my work visually.
```

Or start it yourself and ask the user to select:

```bash
# Start returns a session UUID — capture it and pass to all subsequent commands
SESSION=$(agent-vision start)
agent-vision wait --session $SESSION --timeout 120
```

**Always pass `--session <uuid>` to every command after `start`.** The session UUID isolates your state from other agent instances.

### Element Discovery: The Fast Way to Click

After the area is selected, **use `elements` to discover clickable UI elements** instead of guessing coordinates from screenshots. This is faster, more reliable, and **doesn't steal the user's focus**.

```bash
agent-vision elements --session $SESSION
# Read the JSON output — it lists every button, link, text field, etc. with exact coordinates
# Pick the element you want by its label and index
agent-vision control click --element 3 --session $SESSION
# Uses AX API directly — no cursor movement, user can keep working
```

This works for both native macOS apps and web content in browsers. The accessibility API finds buttons, links, fields, checkboxes, etc. Vision OCR supplements with text that the accessibility tree misses.

**`--element` is focus-free.** When you use `--element`, the agent interacts via the Accessibility API — the system cursor doesn't move and the user's active window stays focused. The user can keep working while the agent clicks buttons and fills forms.

**Re-scan after every action that changes the UI.** After any click, navigation, form submission, or keystroke that could change what's on screen, run `agent-vision elements --session $SESSION` again before your next interaction. Element indices change when the UI updates — stale indices will click the wrong thing. The pattern is always: **scan → act → re-scan → act → re-scan → ...**

**When to use `elements` vs manual coordinates:**
- **Use `--element N`** for clicking buttons, links, form fields, menu items — anything interactive. Focus-free.
- **Use `--at X,Y`** only as a last resort when the element genuinely isn't in the scan (custom-drawn UIs, canvas elements). This DOES steal focus.

**Always scan before falling back to `--at`.** Do not guess coordinates from a screenshot without first running `elements` and confirming your target isn't in the results. If you find yourself repeatedly clicking `--at` coordinates and missing, stop — re-scan, look for the right element by label, and use `--element`. The scan is almost always faster and more accurate than coordinate guessing.

**OCR text vs interactive elements.** The `elements` scan returns two kinds of results: accessibility elements (buttons, links, fields — these are interactive) and OCR text (static text found by Vision — these just give you coordinates). When you see a target as OCR `staticText`, look for a nearby accessibility element that covers the same area (e.g., a `group`, `link`, or `button` wrapping the text). Use `--element` on the interactive parent rather than `--at` on the OCR text coordinates — this avoids hitting adjacent interactive elements (checkboxes, stars, action buttons) that share the same row.

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
agent-vision capture --session $SESSION --output /tmp/before.png

# 2. Make your code changes...

# 3. Wait a moment for the UI to refresh
sleep 2

# 4. Capture the result
agent-vision capture --session $SESSION --output /tmp/after.png

# 5. Read both screenshots to compare
# Use the Read tool on both PNGs to see them
```

### Workflow: Recreating a UI Element

When asked to recreate or match an existing design:

```bash
# Capture the reference design
agent-vision capture --session $SESSION --output /tmp/reference.png
# Read it to understand the layout, colors, spacing, typography
# Then implement and capture your result to compare
```

### Workflow: Periodic Monitoring

For longer tasks, capture periodically to verify progress:

```bash
# After each significant change
agent-vision capture --session $SESSION
# Read the resulting PNG to check your work
```

### Workflow: Interactive UI Navigation

Every interaction follows the **scan → act → re-scan** loop. Never reuse element indices from a previous scan after the UI has changed.

```bash
# 1. Scan to see what's on screen
agent-vision elements --session $SESSION

# 2. Act on an element
agent-vision control click --session $SESSION --element 3

# 3. Wait for UI to update
sleep 0.5

# 4. Re-scan — the UI changed, old indices are stale
agent-vision elements --session $SESSION
# Now you see the NEW elements. Pick your next target from THIS scan.

# 5. Act again
agent-vision control click --session $SESSION --element 1

# 6. Re-scan again...
agent-vision elements --session $SESSION
# Repeat for every interaction. Never skip the re-scan.
```

**Example: Navigating Finder folders**
```bash
agent-vision elements --session $SESSION           # see files and folders
agent-vision control click --session $SESSION --element 5   # open "Documents" folder
sleep 0.5
agent-vision elements --session $SESSION           # NOW see contents of Documents
agent-vision control click --session $SESSION --element 3   # open "Projects" subfolder
sleep 0.5
agent-vision elements --session $SESSION           # see contents of Projects
```

**Fallback: Manual coordinate targeting** (when element isn't in the scan):

```bash
# Preview — the green DOT must be on the target element
agent-vision preview --session $SESSION --at 400,150
# Read the preview. If the dot is off, recalculate and preview again.

# Only click once the dot is confirmed on target
agent-vision control click --session $SESSION --at 400,150
```

### Workflow: Filling a Form

```bash
# Discover form elements
agent-vision elements --session $SESSION
# JSON shows: index 1 = textField "Name", index 2 = textField "Email", index 3 = button "Submit"

# Set field values directly (focus-free — doesn't steal cursor)
agent-vision control type --session $SESSION --text "John Doe" --element 1
agent-vision control type --session $SESSION --text "john@example.com" --element 2

# Click submit
agent-vision control click --session $SESSION --element 3

# Capture to verify
sleep 1
agent-vision capture --session $SESSION
```

Note: `type --element` replaces the field's entire value. To append text to an existing value, use `type --text` without `--element` (requires prior focus via click).

### Workflow: Scrolling

Use `scroll --delta` for normal scrolling:

```bash
# Scroll down
agent-vision control scroll --session $SESSION --delta 0,-300

# Scroll up
agent-vision control scroll --session $SESSION --delta 0,300

sleep 0.5
agent-vision capture --session $SESSION
```

**Emulators and simulators need drag-to-scroll.** If the capture area contains a mobile emulator/simulator (iOS Simulator, Android Emulator, Expo Go, device preview frames), use `drag` instead of `scroll` — these interfaces respond to touch/swipe gestures, not scroll wheel events.

```bash
# Scroll down in an emulator (swipe up = drag from bottom to top)
agent-vision control drag --session $SESSION --from 200,500 --to 200,200

# Scroll up in an emulator (drag from top to bottom)
agent-vision control drag --session $SESSION --from 200,200 --to 200,500

# Horizontal swipe (e.g. carousel, page navigation)
agent-vision control drag --session $SESSION --from 350,300 --to 50,300

sleep 0.5
agent-vision capture --session $SESSION
```

### Control Coordinates

- All positions are relative to the **top-left corner** of the selected area
- `(0, 0)` = top-left corner of the area
- `(area_width-1, area_height-1)` = bottom-right corner
- **All actions are bounds-checked** — you cannot accidentally interact outside the selected area

### Targeting Elements

**Preferred: Use `elements` for exact targeting.** Run `agent-vision elements --session $SESSION` to get a JSON list of every interactive element with its exact center coordinates. Pick the element by its role and label, then `click --element N`. No guessing, no previewing, no iteration.

```bash
agent-vision elements --session $SESSION                    # scan
agent-vision control click --session $SESSION --element 5   # click — done
```

**Always re-scan after UI changes.** Element indices may change after clicks, navigation, or page loads. Run `elements` again before each interaction.

**Fallback: Manual coordinates.** Only after confirming `elements` doesn't cover your target (custom-drawn UIs, canvas elements), use `--at X,Y`:
1. The screenshot maps 1:1 to the area coordinate space — pixel position = click coordinate
2. Use `agent-vision preview --session $SESSION --at X,Y` to verify before clicking
3. The green **dot** marks the click point (the label may be offset)
4. Recalculate if the dot is off — don't nudge by small amounts
5. If you miss repeatedly, stop and re-scan — the element may have appeared in a new scan

### Control Error Handling

| Error | What to do |
|-------|-----------|
| `No element scan found` | Run `agent-vision elements --session $SESSION` before using `--element` |
| `Element N not found` | The index is out of range — re-run `elements` and check the valid range |
| `Stale scan: capture area changed` | The area was reselected since the last scan — run `elements` again |
| `Specify either --at or --element, not both` | Use one targeting mode, not both |
| `coordinates are outside the selected area` | Check your X,Y values against the area dimensions |
| `Accessibility permission required` | Ask user to enable Accessibility for Agent Vision in System Settings > Privacy & Security > Accessibility |
| `action timed out` | The GUI may not be responding — ask user to check if Agent Vision is still running |
| `unknown key` | Check supported key names in `agent-vision control key --help` |

### Ending a Session

**When your goal is completed**, use the `AskUserQuestion` tool to ask the user if they'd like to stop the Agent Vision session:

> "I've completed [goal]. Would you like me to stop the Agent Vision session, or is there anything else you'd like me to do in this window?"

If the user confirms, run `agent-vision stop --session $SESSION`.

**If the goal is not yet completed** and you're stuck or unsure how to proceed, use `AskUserQuestion` to ask for feedback:

> "I'm having trouble [specific issue]. Could you [specific ask — e.g., 'point me to the right element', 'confirm this is the right window', 'describe what you'd like me to click']?"

Do not silently give up or guess wildly. Ask the user.

### Dense List UIs

**In email clients, file managers, and table views, rows are packed with interactive elements.** A single email row may contain a checkbox, a star, a sender name (which opens a contact card), subject text, attachment icons, and date — all within a few pixels of each other. Clicking with `--at` in these UIs is error-prone: you'll hit the wrong element and trigger unintended actions (archiving, starring, opening popups).

**Always use `--element N` for row interactions.** Scan with `elements`, find the right target by its label and role, and click by index. If the scan returns the sender as a `staticText` and a `link` separately, pick the one that matches your intent (e.g., click the row group to open the message, not the sender text which triggers a contact card).

### Verifying Outcomes Visually

**After triggering an action (download, form submit, navigation), verify the result through the UI — not by running shell commands.** Stay within the visual interface:

- **Downloads**: scan `elements` for a browser "Downloads" button/indicator, or look for a download bar at the bottom of the window
- **Form submissions**: capture and check for success messages, redirects, or error states
- **Navigation**: capture to confirm the page changed

Do not use `ls`, `cat`, or other Bash commands to check for side effects. The whole point of Agent Vision is to interact through the screen.

### Key Behaviors

- **Always capture before and after** when making visual changes — this lets you verify the change had the intended effect
- **Read the PNG** using the Read tool after capturing — the path printed by `capture` is what you pass to Read
- **Don't assume the UI updated** — if you don't see your change in the screenshot, the page may not have refreshed yet. Wait and capture again
- **The capture area stays fixed** — if the user scrolls or resizes the window, the capture area doesn't move with it. Ask the user to re-select if needed
- **Screenshots are just PNGs** — you can read them with the Read tool if your agent is multimodal
- **Always describe what you see** — every time you analyze a screenshot, give the user a brief description of what's visible (layout, key elements, colors, state). This confirms you're looking at the right thing and builds shared understanding
- **Acknowledge UI issues honestly** — when the user points out a specific visual problem, look for it in the screenshot and describe what you see. If you can identify the issue, confirm it by describing the specifics. If you can't visually identify what the user is describing, say so honestly rather than guessing — ask for clarification or a new screenshot if needed

### Input and Focus Discipline

**Never type or press keys without verifying focus first.** Sending keystrokes to the wrong element can cause unintended actions.

Follow this sequence for text input:

1. **Scan** with `agent-vision elements --session $SESSION` to find the target field
2. **Click** the field with `agent-vision control click --session $SESSION --element N`
3. **Capture** to confirm the field has focus (look for cursor/caret, focus ring)
4. **Only then type** with `agent-vision control type --session $SESSION --text "..."`
5. **Capture again** to verify text was entered correctly

If you cannot confirm focus visually, **do not type**. Click again or ask the user for help.

### Error Handling

If `capture` fails:

| Error | What to do |
|-------|-----------|
| `Agent Vision is not running` | Run `agent-vision start` and ask user to select an area |
| `No area selected` | Run `agent-vision wait --session $SESSION` or ask user to click "Select Area" or "Select Window" on the toolbar |
| `Screen capture failed — no image returned` | Screen Recording permission not granted — ask user to enable it in System Settings > Privacy & Security > Screen Recording |

### Example: Full UI Development Session

```bash
# Start Agent Vision — capture the session UUID
SESSION=$(agent-vision start)
# Ask user to select the browser area showing the UI

# Wait for selection
agent-vision wait --session $SESSION

# Capture reference state
agent-vision capture --session $SESSION --output /tmp/reference.png
# Read /tmp/reference.png to understand current UI

# Make code changes to the UI...

# Wait for hot reload
sleep 3

# Verify changes
agent-vision capture --session $SESSION --output /tmp/result.png
# Read /tmp/result.png to check the changes

# If you need to interact (click a button, fill a form):
agent-vision elements --session $SESSION
# Pick element by label → click --element N

# When done
agent-vision stop --session $SESSION
```

## Development

```bash
swift build          # Debug build
swift build -c release  # Release build
swift test           # Run tests (24 tests)
```

### Debugging & Logs

The GUI app logs key events to the system log with the `[agent-vision]` prefix. Use these commands to view logs:

```bash
# Live stream logs while agent-vision is running
log stream --predicate 'process == "agent-vision"' --level debug

# View logs after a crash or issue (last 5 minutes)
log show --predicate 'process == "agent-vision"' --last 5m
```

What gets logged:
- App lifecycle (launch, terminate, session ID)
- Area/window selection events with dimensions
- Every action received and its result (click, type, scroll, etc.)
- Element discovery passes (AX + OCR) with element counts and timing
- Slow action warnings (>0.5s)
- Uncaught exceptions with stack traces
- Fatal signals (SIGABRT, SIGBUS, SIGSEGV, SIGILL)

### Project Structure

```
Sources/
├── agent-vision/            # Unified binary (CLI + GUI)
│   ├── CLI.swift            # CLI entry point (ArgumentParser)
│   ├── AppDelegate.swift    # App lifecycle, state management
│   ├── ToolbarWindow.swift  # Floating toolbar panel
│   ├── SelectionOverlay.swift # Drag-to-select overlay
│   ├── BorderWindow.swift   # Dashed border around area
│   ├── ActionWatcher.swift  # File watcher + CGEvent execution
│   ├── ActionFeedbackWindow.swift # Visual ripple overlay
│   └── main.swift           # Entry point dispatcher
└── AgentVisionShared/       # Shared library
    ├── State.swift          # State file IPC (JSON)
    ├── Config.swift         # Paths and constants
    ├── Capture.swift        # CGWindowListCreateImage wrapper + annotated screenshots
    ├── Action.swift         # Action types + file I/O
    ├── KeyMapping.swift     # Key name → virtual key code
    ├── Element.swift        # DiscoveredElement model + JSON coding
    ├── ElementDiscovery.swift # Accessibility API element discovery
    ├── TextDiscovery.swift  # Vision OCR text discovery
    └── ElementStore.swift   # Element scan cache (elements.json)
```

## License

MIT
