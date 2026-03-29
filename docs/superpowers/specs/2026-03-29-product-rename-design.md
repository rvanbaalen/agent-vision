# Product Rename: claude-vision -> agent-vision

## Decision

Rename the product from "Claude Vision" (working title) to **Agent Vision** (`agent-vision`).

## Rationale

- "Claude Vision" ties the product to Anthropic's Claude, but the tool works with any AI coding agent
- "Claude" is Anthropic's trademark, risky for an independent open source project
- "agent-vision" clearly communicates what the product does: gives AI agents vision
- The name is available on Homebrew, npm, and GitHub

## Name System

| Context | Old | New |
|---------|-----|-----|
| CLI command | `claude-vision` | `agent-vision` |
| Homebrew formula | n/a | `agent-vision` |
| GitHub repo | `claude-vision` | `agent-vision` |
| npm package (future) | n/a | `agent-vision` |
| .app bundle | `Claude Vision.app` | `Agent Vision.app` |
| CFBundleIdentifier | `com.claude.vision` | `com.agent-vision.app` |
| Config directory | `~/.claude-vision/` | `~/.agent-vision/` |
| Session directory | `~/.claude-vision/sessions/` | `~/.agent-vision/sessions/` |
| macOS log prefix | `[claude-vision]` | `[agent-vision]` |
| Swift module (shared) | `ClaudeVisionShared` | `AgentVisionShared` |
| Toolbar label | "Claude Vision" | "Agent Vision" |
| Border label | "Claude Vision" | "Agent Vision" |

## Tagline

"Give AI agents eyes on your screen."

## Files to Change

### Package.swift
- Package name: `claude-vision` -> `agent-vision`
- Target names: `claude-vision` -> `agent-vision`, `claude-vision-app` -> remove (merged per distribution design), `ClaudeVisionShared` -> `AgentVisionShared`
- Test target: `ClaudeVisionTests` -> `AgentVisionTests`

### Sources/
- Directory rename: `Sources/claude-vision/` -> `Sources/agent-vision/`
- Directory rename: `Sources/claude-vision-app/` -> merged into `Sources/agent-vision/`
- Directory rename: `Sources/ClaudeVisionShared/` -> `Sources/AgentVisionShared/`

### Config.swift
- `basePath`: `~/.claude-vision/` -> `~/.agent-vision/`
- All derived paths (state, actions, elements, sessions)

### CLI.swift
- `commandName`: `"claude-vision"` -> `"agent-vision"`
- App bundle path references
- Error messages mentioning the product name

### GUI files (ToolbarWindow.swift, BorderWindow.swift, AppDelegate.swift, main.swift)
- String literals with "Claude Vision" -> "Agent Vision"
- String literals with "claude-vision" -> "agent-vision"
- Log prefixes

### Info.plist (in Homebrew formula)
- `CFBundleName`: `Claude Vision` -> `Agent Vision`
- `CFBundleIdentifier`: `com.claude.vision` -> `com.agent-vision.app`
- `NSScreenCaptureUsageDescription`: update text

### README.md
- All references to "Claude Vision" and "claude-vision"
- Install instructions
- CLI examples

### Tests
- Directory rename: `Tests/ClaudeVisionTests/` -> `Tests/AgentVisionTests/`
- Import statements

### Distribution design doc
- Update `~/.gstack/projects/claude-vision/robin-main-design-20260328-191518.md` with new name

## What Does NOT Change

- Architecture (CLI + GUI, file-based IPC)
- Swift code logic (capture, accessibility, elements, actions)
- CLI subcommands (start, wait, capture, elements, control, stop, etc.)
- macOS API usage (CoreGraphics, AppKit, Vision, ApplicationServices)

## Scope

This is a mechanical find-and-replace rename. No behavioral changes, no new features, no architectural changes. The binary merge (from the Homebrew distribution design doc) is a separate task that can be done before or after the rename.
