import AppKit
import AgentVisionShared

// Global session ID — set from main.swift, read by signal handler
nonisolated(unsafe) var globalSessionID: String = ""

// Signal handler for SIGTERM — must be a C function (no captures)
private func handleSIGTERM(_: Int32) {
    if !globalSessionID.isEmpty {
        try? FileManager.default.removeItem(at: Config.sessionDirectory(for: globalSessionID))
    }
    DispatchQueue.main.async { NSApp.terminate(nil) }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var sessionID: String = ""
    var toolbarWindow: ToolbarWindow!
    var selectionOverlay: SelectionOverlay?
    var windowSelectionController: WindowSelectionController?
    var borderWindow: BorderWindow?
    var actionWatcher: ActionWatcher?
    var feedbackWindow: ActionFeedbackWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[claude-vision] applicationDidFinishLaunching — session=\(sessionID)")
        globalSessionID = sessionID

        // Write PID to state file for this session
        let state = AppState(pid: ProcessInfo.processInfo.processIdentifier, area: nil)
        let sessionDir = Config.sessionDirectory(for: sessionID)
        do {
            try StateFile.write(state, to: Config.stateFilePath(for: sessionID), createDirectory: sessionDir)
            NSLog("[claude-vision] State file written to \(Config.stateFilePath(for: sessionID).path)")
        } catch {
            NSLog("[claude-vision] FATAL: Failed to write state file: \(error)")
            NSApp.terminate(nil)
            return
        }

        // Set up signal handler for cleanup
        signal(SIGTERM, handleSIGTERM)

        // Create and show toolbar
        NSLog("[claude-vision] Creating toolbar window")
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
            selector: #selector(beginWindowSelection),
            name: .beginWindowSelection,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionWasCancelled),
            name: .selectionCancelled,
            object: nil
        )

        actionWatcher = ActionWatcher(sessionID: sessionID)
        actionWatcher?.start { [weak self] action, area in
            self?.showActionFeedback(action: action, area: area)
        }
        NSLog("[claude-vision] App launch complete, action watcher started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("[claude-vision] applicationWillTerminate — cleaning up session=\(sessionID)")
        actionWatcher?.stop()
        // Clean up entire session directory
        try? FileManager.default.removeItem(at: Config.sessionDirectory(for: sessionID))
        NSLog("[claude-vision] Cleanup complete")
    }

    func showActionFeedback(action: ActionRequest, area: CaptureArea) {
        if feedbackWindow == nil {
            feedbackWindow = ActionFeedbackWindow()
        }

        let screenPoint: CGPoint
        switch action {
        case .click(let pt):
            screenPoint = CGPoint(x: area.x + pt.x, y: area.y + pt.y)
        case .scroll(_, let pt):
            screenPoint = CGPoint(x: area.x + pt.x, y: area.y + pt.y)
        case .drag(let from, _):
            screenPoint = CGPoint(x: area.x + from.x, y: area.y + from.y)
        case .type, .key, .discoverElements, .clickElement, .typeElement:
            screenPoint = CGPoint(x: area.x + area.width / 2, y: area.y + area.height / 2)
        }

        feedbackWindow?.showRipple(at: screenPoint)
    }

    @objc func beginSelection() {
        NSLog("[claude-vision] beginSelection — area drag mode")
        let screen = NSScreen.main ?? NSScreen.screens[0]
        selectionOverlay = SelectionOverlay(screen: screen)
        selectionOverlay?.beginSelection()
    }

    @objc func beginWindowSelection() {
        NSLog("[claude-vision] beginWindowSelection — window pick mode")
        windowSelectionController = WindowSelectionController()
        windowSelectionController?.begin()
    }

    @objc func areaWasSelected(_ notification: Notification) {
        guard let area = notification.object as? CaptureArea else {
            NSLog("[claude-vision] areaWasSelected — notification had no CaptureArea!")
            return
        }
        NSLog("[claude-vision] areaWasSelected — \(Int(area.width))x\(Int(area.height)) at (\(Int(area.x)),\(Int(area.y)))")

        selectionOverlay?.endSelection()
        selectionOverlay = nil
        windowSelectionController?.end()
        windowSelectionController = nil

        // Update state file with area for this session
        let state = AppState(pid: ProcessInfo.processInfo.processIdentifier, area: area)
        do {
            try StateFile.write(state, to: Config.stateFilePath(for: sessionID), createDirectory: Config.sessionDirectory(for: sessionID))
        } catch {
            NSLog("[claude-vision] ERROR: Failed to write area to state: \(error)")
        }

        // Show toolbar again with dimensions
        toolbarWindow.updateSelectButtonTitle("\(Int(area.width))\u{00d7}\(Int(area.height))")
        toolbarWindow.showToolbar()

        // Show border window
        borderWindow?.orderOut(nil)
        borderWindow = BorderWindow(area: area)
        borderWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func selectionWasCancelled() {
        NSLog("[claude-vision] selectionWasCancelled")
        selectionOverlay?.endSelection()
        selectionOverlay = nil
        windowSelectionController?.end()
        windowSelectionController = nil
        toolbarWindow.showToolbar()
    }

}
