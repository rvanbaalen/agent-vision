@preconcurrency import Foundation
import ArgumentParser
import CoreGraphics
import AgentVisionShared

@main
struct ClaudeVision: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "claude-vision",
        abstract: "Screen region capture tool for Claude Code",
        subcommands: [Start.self, Wait.self, Capture.self, Calibrate.self, Preview.self, Stop.self, Control.self, Elements.self]
    )
}

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Launch the toolbar GUI and create a new session")

    func run() throws {
        // Clean up stale sessions
        Config.cleanStaleSessions()

        // Generate session UUID
        let sessionID = UUID().uuidString.lowercased()
        let sessionDir = Config.sessionDirectory(for: sessionID)

        // Write initial state
        let state = AppState(pid: ProcessInfo.processInfo.processIdentifier, area: nil)
        try StateFile.write(state, to: Config.stateFilePath(for: sessionID), createDirectory: sessionDir)

        // Launch GUI with session ID
        let appBundlePath = "/Applications/Claude Vision.app"
        if FileManager.default.fileExists(atPath: appBundlePath) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", "-a", appBundlePath, "--args", "--session", sessionID]
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
            process.arguments = ["--session", sessionID]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        }

        // Print session ID to stdout — Claude captures this
        print(sessionID)
    }
}

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop a session")

    @Option(name: .long, help: "Session ID")
    var session: String

    func run() throws {
        try validateSession(session)

        let statePath = Config.stateFilePath(for: session)
        if let state = try StateFile.read(from: statePath),
           StateFile.isProcessRunning(pid: state.pid) {
            kill(state.pid, SIGTERM)
        }

        // Remove entire session directory
        try? FileManager.default.removeItem(at: Config.sessionDirectory(for: session))
        print("Session stopped.")
    }
}

struct Wait: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Wait for area selection")

    @Option(name: .long, help: "Session ID")
    var session: String

    @Option(name: .long, help: "Timeout in seconds (default: 60)")
    var timeout: Int = 60

    func run() throws {
        try validateSession(session)
        let statePath = Config.stateFilePath(for: session)
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))

        while Date() < deadline {
            guard let state = try StateFile.read(from: statePath),
                  StateFile.isProcessRunning(pid: state.pid) else {
                fputs("Session is not running. Use 'claude-vision start' first.\n", stderr)
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

    @Option(name: .long, help: "Session ID")
    var session: String

    @Option(name: .long, help: "Output file path (default: temp file)")
    var output: String?

    func run() throws {
        let area = try requireArea(session: session)

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

    @Option(name: .long, help: "Session ID")
    var session: String

    @Option(name: .long, help: "Output file path (default: temp file)")
    var output: String?

    func run() throws {
        let area = try requireArea(session: session)
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

    @Option(name: .long, help: "Session ID")
    var session: String

    @Option(name: .long, help: "Position as X,Y relative to area top-left")
    var at: String

    @Option(name: .long, help: "Output file path (default: temp file)")
    var output: String?

    func run() throws {
        let area = try requireArea(session: session)
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

// MARK: - Session helpers

/// Validate session ID format and existence.
func validateSession(_ sessionID: String) throws {
    guard Config.isValidSessionID(sessionID) else {
        fputs("Invalid session ID.\n", stderr)
        throw ExitCode.failure
    }
    guard FileManager.default.fileExists(atPath: Config.sessionDirectory(for: sessionID).path) else {
        fputs("Session not found. Run 'claude-vision start' first.\n", stderr)
        throw ExitCode.failure
    }
}

/// Validate session, read state, check running + area selected, return area.
func requireArea(session sessionID: String) throws -> CaptureArea {
    try validateSession(sessionID)
    let statePath = Config.stateFilePath(for: sessionID)
    guard let state = try StateFile.read(from: statePath),
          StateFile.isProcessRunning(pid: state.pid) else {
        fputs("Session is not running. Use 'claude-vision start' first.\n", stderr)
        throw ExitCode.failure
    }
    guard let area = state.area else {
        fputs("No area selected. Select an area using the toolbar.\n", stderr)
        throw ExitCode.failure
    }
    return area
}

/// Send an action to the GUI and wait for the result.
func sendAction(_ action: ActionRequest, area: CaptureArea, session sessionID: String, quiet: Bool = false) throws {
    if let error = action.boundsError(for: area) {
        fputs("\(error)\n", stderr)
        throw ExitCode.failure
    }

    let actionPath = Config.actionFilePath(for: sessionID)
    let resultPath = Config.actionResultFilePath(for: sessionID)
    let sessionDir = Config.sessionDirectory(for: sessionID)

    ActionFile.delete(at: actionPath)
    ActionFile.delete(at: resultPath)

    try ActionFile.write(action, to: actionPath, createDirectory: sessionDir)

    // Element discovery and element-based actions need longer timeouts
    // (AX tree re-walk on complex apps like Mail can take 5-10s)
    let timeout: TimeInterval
    if action.isDiscoverElements {
        timeout = 30
    } else if action.isElementBased {
        timeout = 15
    } else {
        timeout = 10
    }
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: resultPath.path) {
            let result = try ActionFile.readResult(from: resultPath)
            ActionFile.delete(at: resultPath)
            if result.success {
                if !quiet { print(result.message) }
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

/// Resolve an element index from the cached scan.
func resolveElement(index: Int, area: CaptureArea, session sessionID: String) throws -> DiscoveredElement {
    let elementsPath = Config.elementsFilePath(for: sessionID)
    guard let scanResult = try ElementStore.read(from: elementsPath) else {
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

        @Option(name: .long, help: "Session ID")
        var session: String

        @Option(name: .long, help: "Position as X,Y relative to area top-left")
        var at: String?

        @Option(name: .long, help: "Element index from last 'elements' scan (focus-free)")
        var element: Int?

        func run() throws {
            let area = try requireArea(session: session)

            if let elementIndex = element {
                guard at == nil else {
                    fputs("Specify either --at or --element, not both.\n", stderr)
                    throw ExitCode.failure
                }
                try sendAction(.clickElement(index: elementIndex), area: area, session: session)
            } else if let atStr = at {
                let point = try parsePoint(atStr)
                try sendAction(.click(at: point), area: area, session: session)
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

        @Option(name: .long, help: "Session ID")
        var session: String

        @Option(name: .long, help: "Text to type")
        var text: String

        @Option(name: .long, help: "Element index from last 'elements' scan (focus-free, replaces field value)")
        var element: Int?

        func run() throws {
            let area = try requireArea(session: session)

            if let elementIndex = element {
                try sendAction(.typeElement(text: text, index: elementIndex), area: area, session: session)
            } else {
                try sendAction(.type(text: text), area: area, session: session)
            }
        }
    }

    struct Key: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Press a key or key combination")

        @Option(name: .long, help: "Session ID")
        var session: String

        @Option(name: .long, help: "Key to press (e.g. enter, tab, cmd+a, shift+tab)")
        var key: String

        func run() throws {
            do {
                _ = try KeyMapping.parse(key)
            } catch {
                fputs("\(error)\n", stderr)
                throw ExitCode.failure
            }
            let area = try requireArea(session: session)
            try sendAction(.key(key: key), area: area, session: session)
        }
    }

    struct Scroll: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Scroll by pixel delta")

        @Option(name: .long, help: "Session ID")
        var session: String

        @Option(name: .long, help: "Scroll delta as DX,DY (negative Y = scroll down)")
        var delta: String

        @Option(name: .long, help: "Position as X,Y (default: center of area)")
        var at: String?

        func run() throws {
            let area = try requireArea(session: session)
            let d = try parseDelta(delta)
            let point: Point
            if let atStr = at {
                point = try parsePoint(atStr)
            } else {
                point = Point(x: area.width / 2, y: area.height / 2)
            }
            try sendAction(.scroll(delta: d, at: point), area: area, session: session)
        }
    }

    struct Drag: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Click and drag between two points")

        @Option(name: .long, help: "Session ID")
        var session: String

        @Option(name: .long, help: "Start position as X,Y")
        var from: String

        @Option(name: .long, help: "End position as X,Y")
        var to: String

        func run() throws {
            let area = try requireArea(session: session)
            let fromPt = try parsePoint(from)
            let toPt = try parsePoint(to)
            try sendAction(.drag(from: fromPt, to: toPt), area: area, session: session)
        }
    }
}

struct Elements: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Discover interactive elements in the selected area"
    )

    @Option(name: .long, help: "Session ID")
    var session: String

    @Flag(name: .long, help: "Save annotated screenshot with numbered badges")
    var annotated: Bool = false

    @Option(name: .long, help: "Output file path for annotated screenshot")
    var output: String?

    func run() throws {
        let area = try requireArea(session: session)

        // Send discovery request to GUI (which has AX permissions)
        try sendAction(.discoverElements, area: area, session: session, quiet: true)

        // Read results written by GUI
        let elementsPath = Config.elementsFilePath(for: session)
        guard let result = try ElementStore.read(from: elementsPath) else {
            fputs("Error: Element discovery produced no results.\n", stderr)
            throw ExitCode.failure
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try encoder.encode(result)
        print(String(data: json, encoding: .utf8)!)

        if annotated {
            let outputPath: String
            if let p = output {
                outputPath = p
            } else {
                outputPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent("claude-vision-elements-\(Int(Date().timeIntervalSince1970)).png").path
            }
            try ScreenCapture.captureWithElements(area: area, elements: result.elements, to: URL(fileURLWithPath: outputPath))
            fputs("Annotated screenshot: \(outputPath)\n", stderr)
        }
    }
}
