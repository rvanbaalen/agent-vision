import AppKit

// Parse --session <uuid> from command-line arguments
var sessionID: String?
let args = CommandLine.arguments
if let idx = args.firstIndex(of: "--session"), idx + 1 < args.count {
    sessionID = args[idx + 1]
}

guard let sid = sessionID else {
    fputs("Usage: claude-vision-app --session <uuid>\n", stderr)
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
delegate.sessionID = sid
app.delegate = delegate
app.run()
