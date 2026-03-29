import AppKit

NSLog("[agent-vision] App starting, args: \(CommandLine.arguments)")

// Parse --session <uuid> from command-line arguments
var sessionID: String?
let args = CommandLine.arguments
if let idx = args.firstIndex(of: "--session"), idx + 1 < args.count {
    sessionID = args[idx + 1]
}

guard let sid = sessionID else {
    fputs("Usage: agent-vision --session <uuid>\n", stderr)
    exit(1)
}

NSLog("[agent-vision] Session: \(sid)")

// Install global exception/signal handlers for crash diagnostics
NSSetUncaughtExceptionHandler { exception in
    NSLog("[agent-vision] UNCAUGHT EXCEPTION: \(exception)")
    NSLog("[agent-vision] Stack trace: \(exception.callStackSymbols.joined(separator: "\n"))")
}

for sig: Int32 in [SIGABRT, SIGBUS, SIGSEGV, SIGILL] {
    signal(sig) { sigNum in
        NSLog("[agent-vision] FATAL SIGNAL \(sigNum) received")
        // Re-raise to get the default crash behavior
        signal(sigNum, SIG_DFL)
        raise(sigNum)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
delegate.sessionID = sid
app.delegate = delegate
NSLog("[agent-vision] Running app loop")
app.run()
