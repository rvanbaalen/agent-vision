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
- **label**: Human-readable text from AX title/description or OCR
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

### Three New Components (Shared Library)

**1. ElementDiscovery.swift — Accessibility API Integration**

- Get frontmost app via `NSWorkspace.shared.frontmostApplication` → `AXUIElementCreateApplication(pid)`
- Recursive tree walk through `AXChildren`, capped at 10 levels deep
- For each element, extract:
  - Role via `kAXRoleAttribute`
  - Label via `kAXTitleAttribute` → `kAXDescriptionAttribute` → `kAXValueAttribute` (fallback chain)
  - Position via `kAXPositionAttribute` (absolute screen point)
  - Size via `kAXSizeAttribute`
- Filter to elements whose bounds intersect the selected capture area
- Convert absolute screen coords to area-relative coords (subtract area origin)
- Prioritize actionable elements (buttons, links, fields, checkboxes, menu items); include static text as secondary
- Deduplicate: if parent and child have identical bounds and label, keep only the child

Note: Browsers expose web content as AX elements (Chrome, Safari), so this covers both native and web UIs.

**2. TextDiscovery.swift — Vision Framework OCR**

- Capture selected area as `CGImage` (reuse `ScreenCapture.capture`)
- Run `VNRecognizeTextRequest` with `.accurate` recognition level
- Convert Vision normalized coords (0-1, bottom-left origin) to area-relative coords (flip Y, scale)
- Deduplicate against accessibility results: skip OCR text if it overlaps >50% with an existing AX element with matching label
- OCR-only elements get `role: "staticText"`
- Expected latency: ~200-400ms, runs alongside accessibility query

**3. ElementStore.swift — Scan Cache**

- Writes to `~/.claude-vision/elements.json` on every `elements` command
- Stores: element list, timestamp, area bounds at scan time
- `click --element N` reads from this cache
- Validates area hasn't changed since scan; rejects with "stale scan" if it has

### Extended Components

**Capture.swift — `captureWithElements` method**

- Draws numbered badges on screenshot at each element's top-left corner
- Badge: 20x20pt rounded rect, white number, blue background (accessibility) or orange (OCR)
- Subtle semi-transparent outline around each element's bounds
- Same drawing pattern as existing `captureWithCalibration` / `captureWithPreview`

**Action.swift — Extended click action**

- `.click` case gains an `.element(Int)` option alongside `.at(Point)`
- Element click resolves to center point via ElementStore lookup

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
- Existing `--at X,Y` unchanged

## File Structure

```
Sources/ClaudeVisionShared/
  ├── ElementDiscovery.swift    (new)
  ├── TextDiscovery.swift       (new)
  ├── ElementStore.swift        (new)
  ├── Element.swift             (new — model + JSON coding)
  ├── Capture.swift             (extend — captureWithElements)
  ├── Action.swift              (extend — element click option)
  ├── State.swift               (existing)
  ├── Config.swift              (existing — add elements.json path)
  └── KeyMapping.swift          (existing)

Sources/claude-vision/
  └── CLI.swift                 (extend — Elements command, --element flag on click)

Sources/claude-vision-app/
  └── ActionWatcher.swift       (extend — handle element-based click actions)
```

## Design Decisions

- **JSON stdout, not annotated screenshot, is the primary output.** Claude can pick elements by role/label without looking at images. Annotated screenshots are opt-in for spatial reasoning.
- **Coordinates stay area-relative.** Element centers use the same coordinate space as `--at`, making the two approaches interchangeable.
- **Accessibility API is primary, OCR is supplementary.** AX gives roles and interactivity; OCR only gives text. But OCR catches what AX misses (custom-drawn UIs, Electron apps with poor accessibility).
- **10-level depth cap** prevents runaway traversal in complex apps while catching all interactive elements (typically within 5-6 levels).
- **Stale scan rejection** prevents clicking wrong elements after the area or app changes.

## Edge Cases

- **No elements found**: Return empty list; Claude falls back to `--at X,Y`
- **Element partially outside area**: Include it if center is inside area, exclude otherwise
- **App changes between scan and click**: Stale check catches area changes; app content changes within same area are not detected (acceptable risk)
- **Very dense UIs**: Annotated screenshot may be cluttered; JSON list remains usable regardless
- **Accessibility permission denied**: Already required for existing click functionality; discovery degrades to OCR-only
