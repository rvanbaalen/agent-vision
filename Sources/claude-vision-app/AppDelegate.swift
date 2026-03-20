import AppKit
import ClaudeVisionShared

// Signal handler for SIGTERM — must be a C function (no captures)
private func handleSIGTERM(_: Int32) {
    StateFile.delete(at: Config.stateFilePath)
    DispatchQueue.main.async { NSApp.terminate(nil) }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var toolbarWindow: ToolbarWindow!
    var selectionOverlay: SelectionOverlay?  // Stub — replaced in Task 6
    var borderWindow: BorderWindow?          // Stub — replaced in Task 7

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Write PID to state file
        let state = AppState(pid: ProcessInfo.processInfo.processIdentifier, area: nil)
        do {
            try StateFile.write(state, to: Config.stateFilePath, createDirectory: Config.stateDirectory)
        } catch {
            NSLog("Failed to write state file: \(error)")
            NSApp.terminate(nil)
            return
        }

        // Set up signal handler for cleanup
        signal(SIGTERM, handleSIGTERM)

        // Create and show toolbar
        toolbarWindow = ToolbarWindow()
        toolbarWindow.showToolbar()

        // Register for notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(beginSelection),
            name: .beginAreaSelection,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(areaWasSelected(_:)),
            name: .areaSelected,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionWasCancelled),
            name: .selectionCancelled,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        StateFile.delete(at: Config.stateFilePath)
    }

    @objc func beginSelection() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        selectionOverlay = SelectionOverlay(screen: screen)
        selectionOverlay?.beginSelection()
    }

    @objc func areaWasSelected(_ notification: Notification) {
        guard let area = notification.object as? CaptureArea else { return }

        selectionOverlay?.endSelection()
        selectionOverlay = nil

        // Update state file with area
        let state = AppState(pid: ProcessInfo.processInfo.processIdentifier, area: area)
        do {
            try StateFile.write(state, to: Config.stateFilePath, createDirectory: Config.stateDirectory)
        } catch {
            NSLog("Failed to write area to state: \(error)")
        }

        // Show toolbar again
        toolbarWindow.showToolbar()

        // Show border window
        borderWindow?.orderOut(nil)
        borderWindow = BorderWindow(area: area)
        borderWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func selectionWasCancelled() {
        selectionOverlay?.endSelection()
        selectionOverlay = nil
        toolbarWindow.showToolbar()
    }
}
