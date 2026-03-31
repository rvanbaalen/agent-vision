# Multi-Session GUI + About Window

## Summary

Redesign Agent Vision from one-process-per-session to a single GUI process managing multiple sessions. Add a full macOS menu bar, session dropdown in the toolbar, per-session colored borders, and an About window.

## Motivation

Currently each `agent-vision start` spawns a separate GUI process with its own toolbar. An LLM agent calling `start` multiple times (intentionally or accidentally) creates multiple overlapping toolbars, which is confusing. A single GUI managing all sessions is cleaner for both humans and agents.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| GUI discovery | PID file at `~/.agent-vision/gui.pid` | Direct, unambiguous check |
| New session signaling | File-based polling (Option A) | Consistent with existing IPC, minimal complexity |
| Toolbar session UI | Dropdown picker (Option C) | Compact, full control, shows color + dimensions |
| Dropdown visibility | Always visible, even with one session | Consistent UI, no mode switching |
| New session auto-switch | Yes — toolbar auto-targets the newest pending session | Agent needs to select area for the new session |
| Close button (✕) | Stops selected session; quits app if last session | Per-session control; ⌘Q for force-quit-all |
| Border label | First 8 characters of UUID (e.g. `a1b2c3d4`) | Matches what the agent sees in terminal output |
| Border label switching | Single session: "Agent Vision"; multiple: first 8 of UUID | Less noise in the common single-session case |
| About window link | robinvanbaalen.nl/agent-vision | Project website, not GitHub repo |
| No `quit` command | Last session stopping quits the app | Keep CLI simple; ⌘Q available for manual quit |
| Merge `start` + `wait` | `start` blocks until area selected, then prints UUID | One command instead of two; simpler for agents |
| Start timeout | `--timeout N` flag on `start`, default 60s | Agent shouldn't hang forever if user walks away |

## Architecture

### Process Model

```
Before:  start → spawn GUI process (1:1 session:process)
After:   start → check gui.pid → existing? create session dir : spawn GUI then create session dir
```

Single GUI process, multiple sessions. File-based IPC per session (unchanged).

### File Layout

```
~/.agent-vision/
├── gui.pid                          # NEW — GUI process PID
└── sessions/
    ├── <uuid-1>/
    │   ├── state.json               # AppState: {pid, area, colorIndex}
    │   ├── action.json
    │   ├── action-result.json
    │   └── elements.json
    └── <uuid-2>/
        └── ...
```

### GUI Lifecycle

1. **First `start`**: No living PID in `gui.pid` → spawn GUI process, write `gui.pid`, create session directory
2. **Subsequent `start`**: Living PID in `gui.pid` → just create session directory. GUI detects it via polling.
3. **`stop --session <uuid>`**: CLI removes session directory. GUI detects removal, removes border + dropdown entry. If no sessions remain, GUI quits and removes `gui.pid`.
4. **Toolbar ✕**: Stops the currently selected session (same as `stop`). If last, GUI quits.
5. **⌘Q / Quit menu**: Stops all sessions, GUI quits, removes `gui.pid`.
6. **GUI crash**: `gui.pid` contains dead PID. Next `start` detects this, spawns new GUI.

### Session Discovery (GUI side)

The existing ActionWatcher polling timer (100ms) is extended to also scan `~/.agent-vision/sessions/` for:
- **New directories**: Session directory exists but GUI doesn't have it tracked → adopt it, assign color, create border window, add to dropdown
- **Removed directories**: GUI tracks a session but directory is gone → remove border, remove from dropdown, quit if last

### CLI `start` Flow

```
1. Generate UUID
2. Read gui.pid
3. If PID file exists AND process is alive:
     → Create session directory + state.json
4. Else:
     → Create session directory + state.json
     → Spawn GUI process (agent-vision --gui, no --session flag)
     → Write gui.pid
5. Poll state.json until area is set (with --timeout, default 60s)
6. Print UUID + area dimensions on success
```

Note: GUI is no longer launched with `--session`. It discovers sessions from the filesystem. The `wait` command is removed — `start` blocks until the area is selected.

### Color Assignment

Colors are assigned from a fixed palette in order of session creation:

| Index | Color | Hex |
|-------|-------|-----|
| 0 | Blue | #3B82F6 |
| 1 | Green | #22C55E |
| 2 | Amber | #F59E0B |
| 3 | Red | #EF4444 |
| 4 | Purple | #A855F7 |
| 5 | Cyan | #06B6D4 |
| 6 | Pink | #EC4899 |

Assignment uses a simple counter. When a session is removed, its color index is not recycled (to avoid confusion). If more than 7 sessions exist simultaneously, colors wrap around.

The color index is stored in `state.json` so the border and dropdown can display the correct color.

## Components

### Toolbar Changes

**Current**: Static toolbar with "Select Area", "Select Window", "Close".

**New**: Add session dropdown between "Agent Vision" label and the action buttons.

```
[Agent Vision] | [● a1b2c3d4 · 800×600 ▾] | [Select Area] [Select Window] [✕]
```

- Dropdown shows color dot, first 8 UUID chars, dimensions (or "awaiting selection" if no area yet)
- Dropdown background is tinted to match the session's color
- Click dropdown to expand: shows all sessions, click to switch
- "Select Area" / "Select Window" targets whichever session is selected
- ✕ stops the selected session

**Auto-switch**: When a new session directory appears, the dropdown switches to it automatically (since the new session needs an area selection).

### Border Window Changes

**Current**: Blue dashed border, "Agent Vision" label.

**New**:
- Border color matches session's assigned color from the palette
- Label shows "Agent Vision" when only one session exists
- Label shows first 8 UUID characters (e.g. `a1b2c3d4`) when multiple sessions exist
- Label background pill is tinted to match the session color

### Menu Bar

Full macOS menu bar with three menus:

**Agent Vision menu:**
- About Agent Vision
- Check for Updates…
- ─────
- Quit Agent Vision (⌘Q)

**Session menu:**
- Active Sessions (header)
  - ● Session a1b2c3d4 · 800×600
  - ● Session c3d4e5f6 · 1024×768
- ─────
- Stop Selected Session
- Stop All Sessions

**Help menu:**
- Agent Vision Help
- View on Website

### About Window

Standard macOS About panel (`NSPanel`), centered on screen:

- App icon (gradient blue→purple rounded rect with eye symbol)
- "Agent Vision" title
- "Version X.Y.Z" subtitle
- "by Robin van Baalen"
- Link: robinvanbaalen.nl/agent-vision (clickable, opens browser)
- Divider
- Update status section:
  - Up to date: green checkmark + "Up to date"
  - Update available: amber banner with version number and `brew upgrade agent-vision` command

Update check reuses the existing `checkForUpdate()` function from UpdateCheck.swift but displays the result in the About window instead of printing to stderr.

## CLI Changes

### `agent-vision start [--timeout N]`

- No longer passes `--session <uuid>` to the GUI process
- Checks `gui.pid` before spawning
- Writes `gui.pid` after spawning (only if it spawned)
- Blocks until the user selects an area (absorbs old `wait` behavior)
- `--timeout N` (default 60s) — fails if no area selected within timeout
- On success: prints session UUID and area dimensions
- **`wait` command is removed** — `start` does everything

Output format:
```
a1b2c3d4-e5f6-7890-abcd-ef1234567890
Area selected: 800x600 at (100, 200)
```

### `agent-vision stop --session <uuid>`

- Removes session directory (no longer sends SIGTERM — the GUI PID is shared across sessions)
- GUI detects the removal via polling and cleans up its own state (border, dropdown entry)
- If it was the last session, GUI quits on its own and removes `gui.pid`

### `agent-vision --gui`

- No longer accepts `--session` flag
- Launches as a standalone GUI that discovers sessions from `~/.agent-vision/sessions/`
- Writes `gui.pid` on launch, removes on quit

## Edge Cases

- **GUI crash + restart**: New `start` detects dead PID in `gui.pid`, spawns fresh GUI. New GUI scans existing session directories and adopts them (with fresh color assignments).
- **Stale gui.pid**: Process dead but file exists → `start` overwrites it after spawning new GUI.
- **Race condition on `start`**: Two `start` calls at nearly the same time both see no GUI → both try to spawn. Mitigated by: second spawn detects `gui.pid` was just written by first, skips spawning. If both write, one GUI will find no sessions to manage and quit.
- **Session directory created but GUI hasn't noticed yet**: `start` blocks until area is selected — the GUI polling delay (≤100ms) is invisible since the user still needs to click.
- **All sessions stopped externally**: GUI detects empty session list, quits, removes `gui.pid`.

## What Doesn't Change

- File-based IPC per session (action.json / action-result.json / state.json / elements.json)
- `state.json` still exists per session but the `pid` field now stores the shared GUI PID (from `gui.pid`). CLI session validation uses `gui.pid` for process liveness instead of per-session PIDs.
- All CLI commands except `start` and the removed `wait` (they still operate on a specific session via `--session`)
- ActionWatcher per session (one watcher per tracked session, same polling logic)
- Selection overlays (SelectionOverlay, WindowSelectionOverlay)
- Capture, element discovery, control commands — all unchanged
- The `skill` subcommand and SKILL.md content (will need updating after implementation to reflect multi-session behavior)

## Testing

- Start two sessions, verify single GUI process (check `gui.pid`, `ps aux | grep agent-vision`)
- Verify distinct border colors for each session
- Verify dropdown shows both sessions, switching works
- Stop one session via CLI, verify border removed and dropdown updated
- Stop last session, verify GUI quits
- Kill GUI process, run `start`, verify recovery (new GUI adopts existing sessions)
- About window: verify version, author, link, update check
- ⌘Q quits all sessions
