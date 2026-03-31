import AppKit
import AgentVisionShared

/// Starts the AppKit GUI event loop. This function never returns.
@MainActor
func startGUI() -> Never {
    NSLog("[agent-vision] App starting in GUI mode")

    NSSetUncaughtExceptionHandler { exception in
        NSLog("[agent-vision] UNCAUGHT EXCEPTION: \(exception)")
        NSLog("[agent-vision] Stack trace: \(exception.callStackSymbols.joined(separator: "\n"))")
    }

    for sig: Int32 in [SIGABRT, SIGBUS, SIGSEGV, SIGILL] {
        signal(sig) { sigNum in
            NSLog("[agent-vision] FATAL SIGNAL \(sigNum) received")
            signal(sigNum, SIG_DFL)
            raise(sigNum)
        }
    }

    // Write gui.pid
    let pid = ProcessInfo.processInfo.processIdentifier
    writeGuiPid(pid)

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let delegate = AppDelegate()
    app.delegate = delegate

    NSLog("[agent-vision] Running app loop")
    app.run()

    // Cleanup on exit
    try? FileManager.default.removeItem(at: Config.guiPidFilePath)
    exit(0)
}
