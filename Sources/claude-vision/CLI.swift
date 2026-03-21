@preconcurrency import Foundation
import ArgumentParser
import CoreGraphics
import ClaudeVisionShared

@main
struct ClaudeVision: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "claude-vision",
        abstract: "Screen region capture tool for Claude Code",
        subcommands: [Start.self, Wait.self, Capture.self, Calibrate.self, Preview.self, Stop.self, Control.self, Elements.self]
    )
}

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Launch the toolbar GUI")

    func run() throws {
        // Check if already running
        if let state = try StateFile.read(from: Config.stateFilePath),
           StateFile.isProcessRunning(pid: state.pid) {
            print("Claude Vision is already running (PID \(state.pid))")
            return
        }

        // Clean up stale state
        StateFile.delete(at: Config.stateFilePath)

        // Try to launch via .app bundle first (preserves macOS permissions)
        // Fall back to direct binary launch for dev builds
        let appBundlePath = "/Applications/Claude Vision.app"
        if FileManager.default.fileExists(atPath: appBundlePath) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-a", appBundlePath]
            try process.run()
            process.waitUntilExit()
        } else {
            // Dev fallback: find binary next to CLI
            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            var size = UInt32(MAXPATHLEN)
            guard _NSGetExecutablePath(&pathBuffer, &size) == 0 else {
                throw ValidationError("Cannot determine executable path.")
            }
            let cliPath = String(cString: pathBuffer)
            let cliURL = URL(fileURLWithPath: cliPath).resolvingSymlinksInPath()
            let appURL = cliURL.deletingLastPathComponent().appendingPathComponent("claude-vision-app")

            guard FileManager.default.fileExists(atPath: appURL.path) else {
                throw ValidationError("Cannot find claude-vision-app at \(appURL.path). Install with './scripts/install.sh' or build with 'swift build'.")
            }

            let process = Process()
            process.executableURL = appURL
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        }

        print("Claude Vision started. Use the toolbar to select an area.")
    }
}

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop the GUI")

    func run() throws {
        guard let state = try StateFile.read(from: Config.stateFilePath) else {
            print("Claude Vision is not running.")
            return
        }

        if StateFile.isProcessRunning(pid: state.pid) {
            kill(state.pid, SIGTERM)
        }

        StateFile.delete(at: Config.stateFilePath)
        print("Claude Vision stopped.")
    }
}

struct Wait: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Wait for area selection")

    @Option(name: .long, help: "Timeout in seconds (default: 60)")
    var timeout: Int = 60

    func run() throws {
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))

        while Date() < deadline {
            guard let state = try StateFile.read(from: Config.stateFilePath),
                  StateFile.isProcessRunning(pid: state.pid) else {
                fputs("Claude Vision is not running. Use 'claude-vision start' first.\n", stderr)
                throw ExitCode.failure
            }

            if let area = state.area {
                print("Area selected: \(Int(area.width))x\(Int(area.height)) at (\(Int(area.x)), \(Int(area.y)))")
                return
            }

            Thread.sleep(forTimeInterval: 0.5)
        }

        fputs("No area selected within \(timeout)s\n", stderr)
        throw ExitCode.failure
    }
}

struct Capture: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Capture the selected area")

    @Option(name: .long, help: "Output file path (default: temp file)")
    var output: String?

    func run() throws {
        guard let state = try StateFile.read(from: Config.stateFilePath),
              StateFile.isProcessRunning(pid: state.pid) else {
            fputs("Claude Vision is not running. Use 'claude-vision start' first.\n", stderr)
            throw ExitCode.failure
        }

        guard let area = state.area else {
            fputs("No area selected. Use 'claude-vision start' to launch and select an area.\n", stderr)
            throw ExitCode.failure
        }

        if let outputPath = output {
            try ScreenCapture.capture(area: area, to: URL(fileURLWithPath: outputPath))
            print(outputPath)
        } else {
            let path = try ScreenCapture.captureToTemp(area: area)
            print(path)
        }
    }
}

struct Calibrate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Capture with coordinate grid for calibration"
    )

    @Option(name: .long, help: "Output file path (default: temp file)")
    var output: String?

    func run() throws {
        let area = try requireArea()
        let outputPath: String
        if let p = output {
            outputPath = p
        } else {
            outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("claude-vision-calibrate-\(Int(Date().timeIntervalSince1970)).png").path
        }

        try ScreenCapture.captureWithCalibration(area: area, to: URL(fileURLWithPath: outputPath))

        let w = Int(area.width)
        let h = Int(area.height)
        print(outputPath)
        print("Crosshairs at: (\(w/4),\(h/4)) (\(w*3/4),\(h/4)) (\(w/4),\(h*3/4)) (\(w*3/4),\(h*3/4))")
        print("Use these reference points to estimate click coordinates for `claude-vision control click --at X,Y`")
    }
}

struct Preview: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Preview a click position — shows crosshair without clicking"
    )

    @Option(name: .long, help: "Position as X,Y relative to area top-left")
    var at: String

    @Option(name: .long, help: "Output file path (default: temp file)")
    var output: String?

    func run() throws {
        let area = try requireArea()
        let point = try parsePoint(at)

        let outputPath: String
        if let p = output {
            outputPath = p
        } else {
            outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("claude-vision-preview-\(Int(Date().timeIntervalSince1970)).png").path
        }

        try ScreenCapture.captureWithPreview(
            area: area,
            at: (x: Int(point.x), y: Int(point.y)),
            to: URL(fileURLWithPath: outputPath)
        )
        print(outputPath)
    }
}

// MARK: - Control helpers

/// Shared logic: read state, validate app running + area selected, return area.
func requireArea() throws -> CaptureArea {
    guard let state = try StateFile.read(from: Config.stateFilePath),
          StateFile.isProcessRunning(pid: state.pid) else {
        fputs("Claude Vision is not running. Use 'claude-vision start' first.\n", stderr)
        throw ExitCode.failure
    }
    guard let area = state.area else {
        fputs("No area selected. Use 'claude-vision start' to launch and select an area.\n", stderr)
        throw ExitCode.failure
    }
    return area
}

/// Send an action to the GUI and wait for the result.
func sendAction(_ action: ActionRequest, area: CaptureArea) throws {
    if let error = action.boundsError(for: area) {
        fputs("\(error)\n", stderr)
        throw ExitCode.failure
    }

    ActionFile.delete(at: Config.actionFilePath)
    ActionFile.delete(at: Config.actionResultFilePath)

    try ActionFile.write(action, to: Config.actionFilePath, createDirectory: Config.stateDirectory)

    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: Config.actionResultFilePath.path) {
            let result = try ActionFile.readResult(from: Config.actionResultFilePath)
            ActionFile.delete(at: Config.actionResultFilePath)
            if result.success {
                print(result.message)
            } else {
                fputs("\(result.message)\n", stderr)
                throw ExitCode.failure
            }
            return
        }
        Thread.sleep(forTimeInterval: 0.05)
    }

    fputs("Error: action timed out — GUI may not be responding\n", stderr)
    throw ExitCode.failure
}

/// Resolve an element index from the cached scan, with stale/bounds checks.
func resolveElement(index: Int, area: CaptureArea) throws -> DiscoveredElement {
    guard let scanResult = try ElementStore.read(from: Config.elementsFilePath) else {
        fputs("No element scan found. Run 'claude-vision elements' first.\n", stderr)
        throw ExitCode.failure
    }
    if ElementStore.isStale(scanResult, currentArea: area) {
        fputs("Stale scan: capture area changed since last scan. Run 'claude-vision elements' again.\n", stderr)
        throw ExitCode.failure
    }
    guard let el = ElementStore.lookup(index: index, in: scanResult) else {
        fputs("Element \(index) not found. Last scan found \(scanResult.elementCount) elements (1-\(scanResult.elementCount)).\n", stderr)
        throw ExitCode.failure
    }
    return el
}

func parsePoint(_ str: String) throws -> Point {
    let parts = str.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == 2 else {
        throw ValidationError("Invalid position '\(str)'. Expected format: X,Y (e.g. 150,300)")
    }
    return Point(x: parts[0], y: parts[1])
}

func parseDelta(_ str: String) throws -> Delta {
    let parts = str.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == 2 else {
        throw ValidationError("Invalid delta '\(str)'. Expected format: DX,DY (e.g. 0,-100)")
    }
    return Delta(dx: parts[0], dy: parts[1])
}

// MARK: - Control command group

struct Control: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Control the selected area",
        subcommands: [Click.self, TypeText.self, Key.self, Scroll.self, Drag.self]
    )
}

extension Control {
    struct Click: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Left-click at a position")

        @Option(name: .long, help: "Position as X,Y relative to area top-left")
        var at: String?

        @Option(name: .long, help: "Element index from last 'elements' scan (focus-free)")
        var element: Int?

        func run() throws {
            let area = try requireArea()

            if let elementIndex = element {
                guard at == nil else {
                    fputs("Specify either --at or --element, not both.\n", stderr)
                    throw ExitCode.failure
                }
                let el = try resolveElement(index: elementIndex, area: area)
                do {
                    try ElementAction.press(element: el, area: area)
                    print("Clicked \(el.displayLabel) (focus-free)")
                } catch {
                    fputs("\(error)\n", stderr)
                    throw ExitCode.failure
                }
            } else if let atStr = at {
                let point = try parsePoint(atStr)
                try sendAction(.click(at: point), area: area)
            } else {
                fputs("Specify --at X,Y or --element N.\n", stderr)
                throw ExitCode.failure
            }
        }
    }

    struct TypeText: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "type",
            abstract: "Type text at current cursor position"
        )
        @Option(name: .long, help: "Text to type")
        var text: String

        @Option(name: .long, help: "Element index from last 'elements' scan (focus-free, replaces field value)")
        var element: Int?

        func run() throws {
            let area = try requireArea()

            if let elementIndex = element {
                let el = try resolveElement(index: elementIndex, area: area)
                do {
                    try ElementAction.setText(text, element: el, area: area)
                    print("Typed into \(el.displayLabel) (focus-free)")
                } catch {
                    fputs("\(error)\n", stderr)
                    throw ExitCode.failure
                }
            } else {
                try sendAction(.type(text: text), area: area)
            }
        }
    }

    struct Key: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Press a key or key combination")
        @Option(name: .long, help: "Key to press (e.g. enter, tab, cmd+a, shift+tab)")
        var key: String
        func run() throws {
            do {
                _ = try KeyMapping.parse(key)
            } catch {
                fputs("\(error)\n", stderr)
                throw ExitCode.failure
            }
            let area = try requireArea()
            try sendAction(.key(key: key), area: area)
        }
    }

    struct Scroll: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Scroll by pixel delta")
        @Option(name: .long, help: "Scroll delta as DX,DY (negative Y = scroll down)")
        var delta: String
        @Option(name: .long, help: "Position as X,Y (default: center of area)")
        var at: String?
        func run() throws {
            let area = try requireArea()
            let d = try parseDelta(delta)
            let point: Point
            if let atStr = at {
                point = try parsePoint(atStr)
            } else {
                point = Point(x: area.width / 2, y: area.height / 2)
            }
            try sendAction(.scroll(delta: d, at: point), area: area)
        }
    }

    struct Drag: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Click and drag between two points")
        @Option(name: .long, help: "Start position as X,Y")
        var from: String
        @Option(name: .long, help: "End position as X,Y")
        var to: String
        func run() throws {
            let area = try requireArea()
            let fromPt = try parsePoint(from)
            let toPt = try parsePoint(to)
            try sendAction(.drag(from: fromPt, to: toPt), area: area)
        }
    }
}

struct Elements: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Discover interactive elements in the selected area"
    )

    @Flag(name: .long, help: "Save annotated screenshot with numbered badges")
    var annotated: Bool = false

    @Option(name: .long, help: "Output file path for annotated screenshot")
    var output: String?

    func run() throws {
        let area = try requireArea()

        // Run accessibility discovery
        let axElements = ElementDiscovery.discover(area: area)

        // Capture image for OCR
        let rect = CGRect(x: area.x, y: area.y, width: area.width, height: area.height)
        var ocrElements: [DiscoveredElement] = []
        if let image = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, .bestResolution) {
            ocrElements = TextDiscovery.discover(
                image: image,
                areaWidth: area.width,
                areaHeight: area.height,
                existingElements: axElements,
                startIndex: axElements.count + 1
            )
        }

        let allElements = axElements + ocrElements

        // Only warn if both sources found nothing
        if allElements.isEmpty {
            fputs("Warning: No elements found. Check Accessibility permissions or try a different area.\n", stderr)
        }
        let result = ElementScanResult(area: area, elements: allElements)

        // Write cache
        try ElementStore.write(result, to: Config.elementsFilePath, createDirectory: Config.stateDirectory)

        // Output JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(result)
        print(String(data: json, encoding: .utf8)!)

        // Annotated screenshot if requested
        if annotated {
            let outputPath: String
            if let p = output {
                outputPath = p
            } else {
                outputPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent("claude-vision-elements-\(Int(Date().timeIntervalSince1970)).png").path
            }
            try ScreenCapture.captureWithElements(area: area, elements: allElements, to: URL(fileURLWithPath: outputPath))
            fputs("Annotated screenshot: \(outputPath)\n", stderr)
        }
    }
}
