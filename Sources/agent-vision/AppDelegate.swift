import AppKit
import AgentVisionShared

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var toolbarWindow: ToolbarWindow!
    var selectionOverlay: SelectionOverlay?
    var windowSelectionController: WindowSelectionController?
    var feedbackWindow: ActionFeedbackWindow?
    let sessionManager = SessionManager()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // Keep running even when all windows are hidden (accessory mode)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[agent-vision] applicationDidFinishLaunching")

        // Set up signal handler for cleanup
        signal(SIGTERM) { _ in
            try? FileManager.default.removeItem(at: Config.guiPidFilePath)
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }

        // Create and show toolbar
        NSLog("[agent-vision] Creating toolbar window")
        toolbarWindow = ToolbarWindow()
        toolbarWindow.sessionManager = sessionManager
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

        // Start session manager
        sessionManager.onSessionsChanged = { [weak self] in
            self?.toolbarWindow.refreshDropdown()
            self?.sessionManager.refreshBorderLabels()
        }
        sessionManager.onActionFeedback = { [weak self] action, area in
            self?.showActionFeedback(action: action, area: area)
        }
        sessionManager.startScanning()

        NSLog("[agent-vision] App launch complete, session scanner started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSLog("[agent-vision] applicationWillTerminate — cleaning up")
        sessionManager.stopScanning()
        sessionManager.stopAllSessions()
        try? FileManager.default.removeItem(at: Config.guiPidFilePath)
        NSLog("[agent-vision] Cleanup complete")
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
        NSLog("[agent-vision] beginSelection — area drag mode")
        let screen = NSScreen.main ?? NSScreen.screens[0]
        selectionOverlay = SelectionOverlay(screen: screen)
        selectionOverlay?.beginSelection()
    }

    @objc func beginWindowSelection() {
        NSLog("[agent-vision] beginWindowSelection — window pick mode")
        windowSelectionController = WindowSelectionController()
        windowSelectionController?.begin()
    }

    @objc func areaWasSelected(_ notification: Notification) {
        guard let area = notification.object as? CaptureArea else {
            NSLog("[agent-vision] areaWasSelected — notification had no CaptureArea!")
            return
        }
        NSLog("[agent-vision] areaWasSelected — \(Int(area.width))x\(Int(area.height)) at (\(Int(area.x)),\(Int(area.y)))")

        selectionOverlay?.endSelection()
        selectionOverlay = nil
        windowSelectionController?.end()
        windowSelectionController = nil

        // Write area to the selected session's state file
        guard let sid = sessionManager.selectedSessionID,
              let tracked = sessionManager.sessions[sid] else {
            NSLog("[agent-vision] areaWasSelected — no selected session")
            toolbarWindow.showToolbar()
            return
        }

        let guiPid = ProcessInfo.processInfo.processIdentifier
        let state = AppState(pid: guiPid, area: area, colorIndex: tracked.colorIndex)
        do {
            try StateFile.write(state, to: Config.stateFilePath(for: sid), createDirectory: Config.sessionDirectory(for: sid))
        } catch {
            NSLog("[agent-vision] ERROR: Failed to write area to state: \(error)")
        }

        toolbarWindow.showToolbar()
        // Session scanner will pick up the area change and create the border
    }

    @objc func selectionWasCancelled() {
        NSLog("[agent-vision] selectionWasCancelled")
        selectionOverlay?.endSelection()
        selectionOverlay = nil
        windowSelectionController?.end()
        windowSelectionController = nil
        toolbarWindow.showToolbar()
    }
}
