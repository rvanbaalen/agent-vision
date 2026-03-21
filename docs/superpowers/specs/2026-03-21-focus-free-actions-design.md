# Focus-Free Element Actions — Design Spec

## Problem

When Claude uses `click --element N`, the action goes through CGEvent which moves the system cursor and steals focus from whatever the user is doing. Since we already have AX element references from the discovery system, we can act on them directly without touching the cursor.

## Solution

For `--element N` actions, bypass the GUI/CGEvent path entirely. Instead, re-walk the AX tree from the CLI, find the matching `AXUIElement`, and call `AXUIElementPerformAction` or `AXUIElementSetAttributeValue` directly. No cursor movement, no focus steal.

### New Flow

```
Old: CLI → elements.json → resolve center → action.json → GUI → CGEvent (steals focus)
New: CLI → elements.json → re-walk AX tree → match element → AX action (focus-free)
```

`--at X,Y` is unchanged — still uses CGEvent via GUI (steals focus). This is the rare fallback.

## New Component: ElementAction.swift

New file in `ClaudeVisionShared`. Responsible for re-finding an AX element and executing actions on it.

### Re-matching Algorithm

Given cached element metadata (bounds, label, role) and the capture area:

1. Get PID via `ElementDiscovery.findWindowOwnerPID(area:)` (made public)
2. Walk AX tree with same caps (10 depth, 500 elements)
3. For each AX element, compare against cached metadata:
   - Bounds: absolute position within 2px tolerance on each edge (handles minor layout shifts)
   - Label: exact match, or both nil
4. Return the first matching `AXUIElement`
5. If no match: error

### Actions

**Press (click):**
```swift
AXUIElementPerformAction(element, kAXPressAction as CFString)
```
Works for buttons, links, checkboxes, menu items, tabs.

**Focus a text field:**
```swift
AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
```

**Set text value:**
```swift
AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
```
Focus first, then set value. Works for text fields and text areas.

## CLI Changes

### `click --element N`

Instead of resolving to center point and calling `sendAction()`, calls `ElementAction.press(elementMeta:area:)` directly from the CLI process.

- Prints `"Clicked [label] (focus-free)"` on success
- Prints `"Element N not found in current UI. Run 'claude-vision elements' again."` if re-walk fails
- Prints `"Failed to perform action on element N. The element may not be actionable."` if AX action fails

No JSON IPC, no GUI involvement, no cursor movement.

### `type --element N --text "..."`

New option on the `TypeText` command. Sets the text value directly via AX.

- `--element` is optional. Without it, behaves as before (CGEvent keystrokes via GUI)
- With `--element N`: re-finds the element, verifies it's a text field role, focuses it, sets its value
- Prints `"Typed into [label] (focus-free)"` on success
- Prints `"Element N is a [role], not a text field."` if role is wrong

### Unchanged commands

- `elements` — unchanged
- `click --at X,Y` — unchanged (CGEvent via GUI)
- `type --text "..."` (without `--element`) — unchanged (CGEvent via GUI)
- `scroll`, `drag`, `key` — unchanged (no AX equivalent)

## Changes to Existing Files

### `ElementDiscovery.swift`

Make `findWindowOwnerPID(area:)` public so `ElementAction` can reuse it. Currently private.

### `CLI.swift`

- `Click.run()`: when `--element` is used, call `ElementAction.press()` instead of `sendAction()`
- `TypeText`: add optional `--element` flag. When present, call `ElementAction.setText()` instead of `sendAction()`

## Error Messages

| Condition | Message |
|-----------|---------|
| Element not found on re-walk | `"Element N not found in current UI. Run 'claude-vision elements' again."` |
| AX press action fails | `"Failed to perform action on element N. The element may not be actionable."` |
| Type on non-text element | `"Element N is a [role], not a text field."` |
| AX set value fails | `"Failed to set text on element N."` |

## File Structure

```
Sources/ClaudeVisionShared/
  ElementAction.swift         (new — AX re-matching + action execution)
  ElementDiscovery.swift      (modify — make findWindowOwnerPID public)

Sources/claude-vision/
  CLI.swift                   (modify — click/type use ElementAction for --element)
```

## What Stays the Same

- `elements` command and `elements.json` format — unchanged
- GUI app / ActionWatcher — unchanged, still handles `--at` commands
- `scroll`, `drag`, `key` commands — unchanged (CGEvent only)
- Annotated screenshots — unchanged
- All existing tests — unchanged

## Edge Cases

- **Element moved slightly since scan**: 2px tolerance on bounds comparison handles minor shifts
- **Element gone (page navigated)**: Re-walk won't find it → clear error directing re-scan
- **AX action not supported**: Some custom elements may not respond to `kAXPressAction` → error message, user can fall back to `--at`
- **Accessibility permission denied**: Same permission already required for element discovery. If denied, AX actions will fail with a clear error.
- **Text field with existing content**: `AXUIElementSetAttributeValue` replaces the entire value. This matches the existing `type` behavior which appends — document this difference. Users who need to append should use `type --text` without `--element`.
