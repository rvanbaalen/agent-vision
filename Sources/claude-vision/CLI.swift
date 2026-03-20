@preconcurrency import Foundation
import ArgumentParser
import ClaudeVisionShared

@main
struct ClaudeVision: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "claude-vision",
        abstract: "Screen region capture tool for Claude Code",
        subcommands: [Start.self, Wait.self, Capture.self, Stop.self]
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

        // Find the app binary next to this CLI binary
        // Use _NSGetExecutablePath to get the real path regardless of how we were invoked
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        var size = UInt32(MAXPATHLEN)
        guard _NSGetExecutablePath(&pathBuffer, &size) == 0 else {
            throw ValidationError("Cannot determine executable path.")
        }
        let cliPath = String(cString: pathBuffer)
        let cliURL = URL(fileURLWithPath: cliPath).resolvingSymlinksInPath()
        let appURL = cliURL.deletingLastPathComponent().appendingPathComponent("claude-vision-app")

        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw ValidationError("Cannot find claude-vision-app at \(appURL.path). Build it first with 'swift build'.")
        }

        let process = Process()
        process.executableURL = appURL
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

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
