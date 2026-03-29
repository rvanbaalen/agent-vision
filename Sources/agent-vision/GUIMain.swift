import AppKit

NSLog("[claude-vision] App starting, args: \(CommandLine.arguments)")

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

NSLog("[claude-vision] Session: \(sid)")

// Install global exception/signal handlers for crash diagnostics
NSSetUncaughtExceptionHandler { exception in
    NSLog("[claude-vision] UNCAUGHT EXCEPTION: \(exception)")
    NSLog("[claude-vision] Stack trace: \(exception.callStackSymbols.joined(separator: "\n"))")
}

for sig: Int32 in [SIGABRT, SIGBUS, SIGSEGV, SIGILL] {
    signal(sig) { sigNum in
        NSLog("[claude-vision] FATAL SIGNAL \(sigNum) received")
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
NSLog("[claude-vision] Running app loop")
app.run()
