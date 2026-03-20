import ArgumentParser

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
    func run() throws { print("TODO: start") }
}

struct Wait: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Wait for area selection")
    func run() throws { print("TODO: wait") }
}

struct Capture: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Capture the selected area")
    func run() throws { print("TODO: capture") }
}

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop the GUI")
    func run() throws { print("TODO: stop") }
}
