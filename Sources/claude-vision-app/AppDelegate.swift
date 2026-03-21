import AppKit
import ClaudeVisionShared

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
        globalSessionID = sessionID

        // Write PID to state file for this session
        let state = AppState(pid: ProcessInfo.processInfo.processIdentifier, area: nil)
        let sessionDir = Config.sessionDirectory(for: sessionID)
        do {
            try StateFile.write(state, to: Config.stateFilePath(for: sessionID), createDirectory: sessionDir)
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
    }

    func applicationWillTerminate(_ notification: Notification) {
        actionWatcher?.stop()
        // Clean up entire session directory
        try? FileManager.default.removeItem(at: Config.sessionDirectory(for: sessionID))
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
        case .type, .key:
            screenPoint = CGPoint(x: area.x + area.width / 2, y: area.y + area.height / 2)
        }

        feedbackWindow?.showRipple(at: screenPoint)
    }

    @objc func beginSelection() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        selectionOverlay = SelectionOverlay(screen: screen)
        selectionOverlay?.beginSelection()
    }

    @objc func beginWindowSelection() {
        windowSelectionController = WindowSelectionController()
        windowSelectionController?.begin()
    }

    @objc func areaWasSelected(_ notification: Notification) {
        guard let area = notification.object as? CaptureArea else { return }

        selectionOverlay?.endSelection()
        selectionOverlay = nil
        windowSelectionController?.end()
        windowSelectionController = nil

        // Update state file with area for this session
        let state = AppState(pid: ProcessInfo.processInfo.processIdentifier, area: area)
        do {
            try StateFile.write(state, to: Config.stateFilePath(for: sessionID), createDirectory: Config.sessionDirectory(for: sessionID))
        } catch {
            NSLog("Failed to write area to state: \(error)")
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
        selectionOverlay?.endSelection()
        selectionOverlay = nil
        windowSelectionController?.end()
        windowSelectionController = nil
        toolbarWindow.showToolbar()
    }

}
