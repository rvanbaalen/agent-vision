@preconcurrency import Foundation
import ArgumentParser
import CoreGraphics
import AgentVisionShared

@main
struct AgentVision: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "agent-vision",
        abstract: "Give AI agents eyes on your screen",
        subcommands: [Start.self, Capture.self, Calibrate.self, Preview.self, Stop.self, Control.self, Elements.self, SkillInfo.self]
    )

    @Flag(name: .long, help: .hidden)
    var gui: Bool = false

    mutating func run() throws {
        if gui {
            MainActor.assumeIsolated {
                startGUI()
            }
        }
        throw CleanExit.helpRequest()
    }
}

struct Start: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Start a session — launches GUI if needed, waits for area selection")

    @Option(name: .long, help: "Timeout in seconds (default: 60)")
    var timeout: Int = 60

    func run() throws {
        checkForUpdate(owner: "rvanbaalen", repo: "agent-vision")
        Config.cleanStaleSessions()

        let sessionID = UUID().uuidString.lowercased()
        let sessionDir = Config.sessionDirectory(for: sessionID)

        // Determine next color index from existing sessions
        let existingColors = (try? existingSessionColorIndices()) ?? []
        let colorIndex = SessionColors.nextColorIndex(existing: existingColors)

        let guiPid = readGuiPid()
        let guiAlive = guiPid != nil && StateFile.isProcessRunning(pid: guiPid!)

        // Write session state BEFORE spawning GUI so GUI can discover it
        let state = AppState(pid: guiPid ?? ProcessInfo.processInfo.processIdentifier, area: nil, colorIndex: colorIndex)
        try StateFile.write(state, to: Config.stateFilePath(for: sessionID), createDirectory: sessionDir)

        if !guiAlive {
            let pid = try spawnGUI()
            writeGuiPid(pid)
            // Update session state with actual GUI PID
            let updatedState = AppState(pid: pid, area: nil, colorIndex: colorIndex)
            try StateFile.write(updatedState, to: Config.stateFilePath(for: sessionID), createDirectory: sessionDir)
        }

        // Block until area is selected (merged from old Wait command)
        let statePath = Config.stateFilePath(for: sessionID)
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))

        while Date() < deadline {
            guard let currentState = try StateFile.read(from: statePath) else {
                fputs("Session disappeared unexpectedly.\n", stderr)
                throw ExitCode.failure
            }

            if let area = currentState.area {
                print(sessionID)
                print("Area selected: \(Int(area.width))x\(Int(area.height)) at (\(Int(area.x)), \(Int(area.y)))")
                return
            }

            Thread.sleep(forTimeInterval: 0.5)
        }

        fputs("No area selected within \(timeout)s\n", stderr)
        // Clean up the session we created since it was never used
        try? FileManager.default.removeItem(at: sessionDir)
        throw ExitCode.failure
    }
}

// MARK: - GUI PID file helpers

func readGuiPid() -> Int32? {
    guard let data = try? Data(contentsOf: Config.guiPidFilePath),
          let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          let pid = Int32(str) else { return nil }
    return pid
}

func writeGuiPid(_ pid: Int32) {
    try? FileManager.default.createDirectory(at: Config.stateDirectory, withIntermediateDirectories: true)
    try? "\(pid)\n".data(using: .utf8)?.write(to: Config.guiPidFilePath, options: .atomic)
}

func existingSessionColorIndices() throws -> [Int] {
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(at: Config.sessionsDirectory, includingPropertiesForKeys: nil) else {
        return []
    }
    var indices: [Int] = []
    for entry in entries {
        let statePath = entry.appendingPathComponent("state.json")
        if let state = try? StateFile.read(from: statePath) {
            indices.append(state.colorIndex)
        }
    }
    return indices
}

func spawnGUI() throws -> Int32 {
    var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    var size = UInt32(MAXPATHLEN)
    guard _NSGetExecutablePath(&pathBuffer, &size) == 0 else {
        throw ValidationError("Cannot determine executable path.")
    }
    let selfPath = String(decoding: pathBuffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    let selfURL = URL(fileURLWithPath: selfPath).resolvingSymlinksInPath()

    let process = Process()
    process.executableURL = selfURL
    process.arguments = ["--gui"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    return process.processIdentifier
}

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop a session")

    @Option(name: .long, help: "Session ID")
    var session: String

    func run() throws {
        try validateSession(session)
        // Just remove session directory — GUI detects removal via polling
        try? FileManager.default.removeItem(at: Config.sessionDirectory(for: session))
        print("Session stopped.")
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
                .appendingPathComponent("agent-vision-calibrate-\(Int(Date().timeIntervalSince1970)).png").path
        }

        try ScreenCapture.captureWithCalibration(area: area, to: URL(fileURLWithPath: outputPath))

        let w = Int(area.width)
        let h = Int(area.height)
        print(outputPath)
        print("Crosshairs at: (\(w/4),\(h/4)) (\(w*3/4),\(h/4)) (\(w/4),\(h*3/4)) (\(w*3/4),\(h*3/4))")
        print("Use these reference points to estimate click coordinates for `agent-vision control click --at X,Y`")
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
                .appendingPathComponent("agent-vision-preview-\(Int(Date().timeIntervalSince1970)).png").path
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
        fputs("Session not found. Run 'agent-vision start' first.\n", stderr)
        throw ExitCode.failure
    }
}

/// Validate session, read state, check running + area selected, return area.
func requireArea(session sessionID: String) throws -> CaptureArea {
    try validateSession(sessionID)
    let statePath = Config.stateFilePath(for: sessionID)
    guard let state = try StateFile.read(from: statePath),
          StateFile.isProcessRunning(pid: state.pid) else {
        fputs("Session is not running. Use 'agent-vision start' first.\n", stderr)
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
        fputs("No element scan found. Run 'agent-vision elements' first.\n", stderr)
        throw ExitCode.failure
    }
    if ElementStore.isStale(scanResult, currentArea: area) {
        fputs("Stale scan: capture area changed since last scan. Run 'agent-vision elements' again.\n", stderr)
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
                    .appendingPathComponent("agent-vision-elements-\(Int(Date().timeIntervalSince1970)).png").path
            }
            try ScreenCapture.captureWithElements(area: area, elements: result.elements, to: URL(fileURLWithPath: outputPath))
            fputs("Annotated screenshot: \(outputPath)\n", stderr)
        }
    }
}

struct SkillInfo: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skill",
        abstract: "Print AI agent instructions for using agent-vision"
    )

    func run() throws {
        print(skillContent)
    }
}
