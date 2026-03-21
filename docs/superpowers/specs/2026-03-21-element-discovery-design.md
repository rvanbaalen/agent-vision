# Element Discovery System — Design Spec

## Problem

Claude Vision currently requires Claude to estimate pixel coordinates from screenshots to click UI elements. This is slow (multiple preview/adjust cycles) and unreliable (coordinates are often completely wrong). We need a system where Claude can target elements fast and accurately.

## Solution

Add an element discovery layer that uses the macOS Accessibility API and Vision framework OCR to identify interactive elements within the selected capture area. Claude picks elements by index instead of guessing coordinates.

### New Workflow

```
claude-vision elements                    → JSON list of elements with roles, labels, bounds
claude-vision control click --element 5   → click center of element 5
```

Two commands, no coordinate guessing, no preview loops. Existing `--at X,Y` remains as fallback.

## Element Model

```json
{
  "index": 3,
  "source": "accessibility",
  "role": "button",
  "label": "Submit",
  "center": { "x": 245, "y": 162 },
  "bounds": { "x": 200, "y": 148, "width": 90, "height": 28 }
}
```

- **index**: 1-based sequential number for Claude to reference
- **source**: `"accessibility"` or `"ocr"`
- **role**: `button`, `link`, `textField`, `checkbox`, `menuItem`, `staticText`, `image`, `group`, `unknown`
- **label**: Human-readable text from AX title/description or OCR. Elements with no label from any source get `"(unlabeled <role>)"` as their label, e.g. `"(unlabeled button)"`.
- **center**: Click target, relative to selected area (same coordinate space as `--at`)
- **bounds**: Full bounding rect, relative to selected area

Full output:
```json
{
  "area": { "x": 100, "y": 200, "width": 800, "height": 600 },
  "elementCount": 12,
  "elements": [ ... ]
}
```

## Architecture

### Element Resolution: CLI-Side Only

Element index resolution happens entirely in the CLI. When `click --element N` is used, the CLI:
1. Reads `elements.json`
2. Looks up element N's center point
3. Sends a normal `.click(at: centerPoint)` action via JSON IPC

The `ActionRequest` enum, JSON serialization, and `ActionWatcher` remain unchanged. The GUI never sees element indices — it only receives resolved coordinates, same as today.

### CLI Command Changes

**`Click` command**: `--at` becomes optional (`String?`). At runtime, exactly one of `--at` or `--element` must be provided. If both or neither are given, exit with a usage error.

### Three New Components (Shared Library)

**1. ElementDiscovery.swift — Accessibility API Integration**

- Determine the app owning the window under the selected area using `CGWindowListCopyWindowInfo` to find the PID, then `AXUIElementCreateApplication(pid)`. This is more reliable than `frontmostApplication` which may not match the selected area.
- Recursive tree walk through `AXChildren`, capped at 10 levels deep AND 500 total elements (whichever limit is hit first) to handle both deep trees and wide trees
- For each element, extract:
  - Role via `kAXRoleAttribute`
  - Label via `kAXTitleAttribute` → `kAXDescriptionAttribute` → `kAXValueAttribute` (fallback chain). If all are nil, label becomes `"(unlabeled <role>)"`.
  - Position via `kAXPositionAttribute` (absolute screen point, top-left origin — same as `CGWindowListCreateImage`)
  - Size via `kAXSizeAttribute`
  - Hidden state via `kAXHiddenAttribute` — skip elements that are hidden
  - Enabled state via `kAXEnabledAttribute` — include but mark disabled elements
- Filter to elements whose bounds intersect the selected capture area
- Convert absolute screen coords to area-relative coords (subtract area origin). This works correctly on multi-display setups since both AX and capture use global top-left-origin coordinates.
- Prioritize actionable elements (buttons, links, fields, checkboxes, menu items); include static text as secondary
- Deduplicate: if parent and child have identical bounds and label, keep only the child

Note: Browsers expose web content as AX elements (Chrome, Safari), so this covers both native and web UIs.

**2. TextDiscovery.swift — Vision Framework OCR**

Requires `import Vision`. The project targets macOS 13+ so `VNRecognizeTextRequest` is available.

- Capture selected area as `CGImage` at **screen point resolution** (not Retina pixel resolution) via `ScreenCapture.capture`. If the image is at Retina 2x, scale coordinates accordingly: `pointX = pixelX / scaleFactor`.
- Run `VNRecognizeTextRequest` with `.accurate` recognition level
- Convert Vision normalized coords (0-1, bottom-left origin) to area-relative point coords:
  - `x = boundingBox.midX * areaWidth`
  - `y = areaHeight - (boundingBox.midY * areaHeight)`
  - If image is at Retina resolution, divide by scale factor after conversion
- Deduplicate against accessibility results: skip OCR text if any AX element's bounds overlap by >50% of the OCR result's bounds area AND the AX label contains the OCR text (case-insensitive)
- OCR-only elements get `role: "staticText"`
- Expected latency: ~200-400ms

**Concurrency:** Run accessibility and OCR queries sequentially (accessibility first, then OCR). The project uses Swift 6 strict concurrency, and AX calls have main-thread requirements in some contexts. Sequential execution avoids threading complexity for a marginal speed difference (~200ms).

**3. ElementStore.swift — Scan Cache**

- Writes to `~/.claude-vision/elements.json` on every `elements` command
- Stores: element list, timestamp, area bounds at scan time
- `click --element N` reads from this cache
- Validates area hasn't changed since scan; rejects with "stale scan" if it has

### Extended Components

**Capture.swift — `captureWithElements` method**

- Draws numbered badges on screenshot at each element's top-left corner
- Badge: 20x20pt rounded rect, white number, blue background (accessibility) or orange (OCR)
- Collision avoidance: if two badges would overlap, shift the second one right by 22pt. If still overlapping, shift down.
- Subtle semi-transparent outline around each element's bounds
- Same drawing pattern as existing `captureWithCalibration` / `captureWithPreview`

**Config.swift — New path constant**

- Add `elementsFile` path pointing to `~/.claude-vision/elements.json`

**CLI.swift — New and modified commands**

New:
```
claude-vision elements [--annotated] [--output PATH]
```
- Runs accessibility + OCR discovery
- Prints JSON element list to stdout
- `--annotated` saves annotated screenshot, prints path
- `--output` overrides screenshot path

Extended:
```
claude-vision control click --element N
```
- Looks up element N in `elements.json`, clicks its center
- Existing `--at X,Y` unchanged, now optional

### Error Messages

| Condition | Error message |
|-----------|---------------|
| No scan file exists | `"No element scan found. Run 'claude-vision elements' first."` |
| Element index out of range | `"Element N not found. Last scan found M elements (1-M)."` |
| Area changed since scan | `"Stale scan: capture area changed since last scan. Run 'claude-vision elements' again."` |
| Both `--at` and `--element` given | `"Specify either --at or --element, not both."` |
| Neither `--at` nor `--element` given | `"Specify --at X,Y or --element N."` |

## File Structure

```
Sources/ClaudeVisionShared/
  ├── ElementDiscovery.swift    (new)
  ├── TextDiscovery.swift       (new)
  ├── ElementStore.swift        (new)
  ├── Element.swift             (new — model + JSON coding)
  ├── Capture.swift             (extend — captureWithElements)
  ├── Config.swift              (existing — add elements.json path)
  ├── State.swift               (existing)
  └── KeyMapping.swift          (existing)

Sources/claude-vision/
  └── CLI.swift                 (extend — Elements command, --element flag on Click)

Sources/claude-vision-app/
  └── (no changes needed — ActionWatcher receives resolved coordinates as before)
```

## Design Decisions

- **Element resolution in CLI, not GUI.** The CLI reads `elements.json`, resolves the index to a center point, and sends a normal coordinate-based action. ActionRequest, JSON IPC, and ActionWatcher stay unchanged.
- **JSON stdout, not annotated screenshot, is the primary output.** Claude can pick elements by role/label without looking at images. Annotated screenshots are opt-in for spatial reasoning.
- **Coordinates stay area-relative.** Element centers use the same coordinate space as `--at`, making the two approaches interchangeable.
- **Accessibility API is primary, OCR is supplementary.** AX gives roles and interactivity; OCR only gives text. But OCR catches what AX misses (custom-drawn UIs, Electron apps with poor accessibility).
- **Window-under-area PID lookup** instead of `frontmostApplication` ensures we walk the correct app's AX tree even if focus has shifted.
- **Sequential AX + OCR execution** avoids Swift 6 concurrency complexity for a marginal speed difference.
- **Depth cap (10 levels) + element count cap (500)** prevents runaway traversal in both deep and wide trees.
- **Stale scan rejection** prevents clicking wrong elements after the area or app changes.

## Edge Cases

- **No elements found**: Return empty list with `elementCount: 0`; Claude falls back to `--at X,Y`
- **No scan file when clicking by element**: Clear error directing user to run `elements` first
- **Element index out of range**: Error with valid range
- **Element partially outside area**: Include it if center is inside area, exclude otherwise
- **Hidden elements**: Filtered out via `kAXHiddenAttribute`
- **Unlabeled elements**: Get synthetic label `"(unlabeled <role>)"` so they're still targetable by index
- **App changes between scan and click**: Stale check catches area changes; app content changes within same area are not detected (acceptable risk — recommend re-scanning if >10 seconds have passed)
- **Very dense UIs (>500 elements)**: Capped at 500; actionable elements prioritized over static text
- **Annotated screenshot badge overlap**: Badges shift right/down to avoid collision
- **Accessibility permission denied**: Already required for existing click functionality; discovery degrades to OCR-only
- **Multi-display**: Both AX and capture use global top-left-origin coordinates; area-origin subtraction works across displays
