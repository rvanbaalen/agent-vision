import AppKit
import CoreGraphics
import AgentVisionShared

/// Tracks active sessions, their colors, border windows, and action watchers.
@MainActor
class SessionManager {
    struct TrackedSession {
        let sessionID: String
        let colorIndex: Int
        var area: CaptureArea?
        var borderWindow: BorderWindow?
        var actionWatcher: ActionWatcher
        var autoSelect: AutoSelect?
        var autoSelectTimer: Timer?
    }

    private(set) var sessions: [String: TrackedSession] = [:]
    private var scanTimer: Timer?
    var onSessionsChanged: (() -> Void)?
    var onActionFeedback: ((ActionRequest, CaptureArea) -> Void)?

    /// The session ID currently selected in the toolbar dropdown.
    var selectedSessionID: String?

    func startScanning() {
        NSLog("[agent-vision] SessionManager: starting session directory scanner")
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scan()
            }
        }
        // Run an immediate scan
        scan()
    }

    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    private func scan() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: Config.sessionsDirectory, includingPropertiesForKeys: nil
        ) else { return }

        let directoryIDs = Set(entries.map { $0.lastPathComponent })
        let trackedIDs = Set(sessions.keys)

        // Detect new sessions
        for entry in entries {
            let sid = entry.lastPathComponent
            guard Config.isValidSessionID(sid), !trackedIDs.contains(sid) else { continue }
            let statePath = Config.stateFilePath(for: sid)
            guard let state = try? StateFile.read(from: statePath) else { continue }
            adoptSession(id: sid, state: state)
        }

        // Detect removed sessions
        for sid in trackedIDs where !directoryIDs.contains(sid) {
            removeSession(id: sid)
        }

        // Update areas for existing sessions (detect area selection)
        // Collect updates first to avoid mutating `sessions` while iterating it
        var areaUpdates: [(id: String, area: CaptureArea, colorIndex: Int)] = []
        for (sid, tracked) in sessions {
            let statePath = Config.stateFilePath(for: sid)
            guard let state = try? StateFile.read(from: statePath) else { continue }
            if state.area != nil && tracked.area == nil {
                areaUpdates.append((id: sid, area: state.area!, colorIndex: tracked.colorIndex))
            }
        }

        // Apply updates outside the iteration
        for update in areaUpdates {
            let color = SessionColors.color(forIndex: update.colorIndex)
            let label = borderLabel(for: update.id)
            let border = BorderWindow(area: update.area, sessionColor: color, sessionLabel: label)
            sessions[update.id]?.area = update.area
            sessions[update.id]?.borderWindow?.stopTracking()
            sessions[update.id]?.borderWindow?.orderOut(nil)
            sessions[update.id]?.borderWindow = border
            sessions[update.id]?.borderWindow?.orderFrontRegardless()
            NSLog("[agent-vision] SessionManager: area set for \(update.id)")
            onSessionsChanged?()
        }
    }

    private func adoptSession(id: String, state: AppState) {
        NSLog("[agent-vision] SessionManager: adopting session \(id) (color=\(state.colorIndex))")

        let watcher = ActionWatcher(sessionID: id)
        watcher.start { [weak self] action, area in
            self?.onActionFeedback?(action, area)
        }

        var tracked = TrackedSession(
            sessionID: id,
            colorIndex: state.colorIndex,
            area: state.area,
            actionWatcher: watcher
        )

        if let area = state.area {
            let color = SessionColors.color(forIndex: state.colorIndex)
            tracked.borderWindow = BorderWindow(area: area, sessionColor: color, sessionLabel: borderLabel(for: id))
            tracked.borderWindow?.makeKeyAndOrderFront(nil)
        }

        sessions[id] = tracked

        // Start auto-select polling if requested
        if let autoSelect = state.autoSelect {
            sessions[id]?.autoSelect = autoSelect
            startAutoSelect(for: id, hint: autoSelect)
        }

        // Auto-switch to newest session
        selectedSessionID = id
        onSessionsChanged?()
    }

    private func startAutoSelect(for sessionID: String, hint: AutoSelect) {
        NSLog("[agent-vision] SessionManager: starting auto-select for \(sessionID) (app=\(hint.appName))")
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tryAutoSelect(for: sessionID, hint: hint)
            }
        }
        sessions[sessionID]?.autoSelectTimer = timer
        // Also try immediately
        tryAutoSelect(for: sessionID, hint: hint)
    }

    private func tryAutoSelect(for sessionID: String, hint: AutoSelect) {
        guard sessions[sessionID] != nil, sessions[sessionID]?.area == nil else {
            // Already selected or session removed — stop polling
            sessions[sessionID]?.autoSelectTimer?.invalidate()
            sessions[sessionID]?.autoSelectTimer = nil
            return
        }

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        let myPID = ProcessInfo.processInfo.processIdentifier

        for info in list {
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowNum = info[kCGWindowNumber as String] as? UInt32,
                  let ownerName = info[kCGWindowOwnerName as String] as? String,
                  let wx = boundsDict["X"] as? CGFloat,
                  let wy = boundsDict["Y"] as? CGFloat,
                  let ww = boundsDict["Width"] as? CGFloat,
                  let wh = boundsDict["Height"] as? CGFloat,
                  ww > 50, wh > 50 else { continue }

            if pid == myPID { continue }
            if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 { continue }

            // Case-insensitive app name match
            guard ownerName.localizedCaseInsensitiveCompare(hint.appName) == .orderedSame else { continue }

            // Optional title filter
            if let titleFilter = hint.title {
                let windowTitle = info[kCGWindowName as String] as? String ?? ""
                guard windowTitle.localizedCaseInsensitiveContains(titleFilter) else { continue }
            }

            // Match found — create CaptureArea and write state
            let windowTitle = info[kCGWindowName as String] as? String
            let area = CaptureArea(
                x: Double(wx), y: Double(wy),
                width: Double(ww), height: Double(wh),
                windowNumber: windowNum,
                windowOwner: ownerName,
                windowTitle: windowTitle
            )

            NSLog("[agent-vision] SessionManager: auto-selected window \"\(ownerName)\" (\(windowNum)) for \(sessionID)")

            let tracked = sessions[sessionID]!
            let guiPid = ProcessInfo.processInfo.processIdentifier
            let state = AppState(pid: guiPid, area: area, colorIndex: tracked.colorIndex)
            do {
                try StateFile.write(state, to: Config.stateFilePath(for: sessionID), createDirectory: Config.sessionDirectory(for: sessionID))
            } catch {
                NSLog("[agent-vision] ERROR: Failed to write auto-selected area: \(error)")
            }

            // Stop polling
            sessions[sessionID]?.autoSelectTimer?.invalidate()
            sessions[sessionID]?.autoSelectTimer = nil
            // The scan() method will pick up the area change and create the border
            return
        }
    }

    private func removeSession(id: String) {
        NSLog("[agent-vision] SessionManager: removing session \(id)")
        sessions[id]?.autoSelectTimer?.invalidate()
        sessions[id]?.autoSelectTimer = nil
        sessions[id]?.actionWatcher.stop()
        sessions[id]?.borderWindow?.stopTracking()
        sessions[id]?.borderWindow?.orderOut(nil)
        sessions.removeValue(forKey: id)

        if selectedSessionID == id {
            selectedSessionID = sessions.keys.first
        }

        onSessionsChanged?()

        // Quit if no sessions remain
        if sessions.isEmpty {
            NSLog("[agent-vision] SessionManager: no sessions left — quitting")
            try? FileManager.default.removeItem(at: Config.guiPidFilePath)
            NSApp.terminate(nil)
        }
    }

    func stopSession(id: String) {
        try? FileManager.default.removeItem(at: Config.sessionDirectory(for: id))
        // scan() will pick up the removal on next tick
    }

    func stopAllSessions() {
        for sid in sessions.keys {
            try? FileManager.default.removeItem(at: Config.sessionDirectory(for: sid))
        }
    }

    /// Returns the label to show on the pill overlay for a session.
    func borderLabel(for sessionID: String) -> String {
        "Agent Vision · \(sessionID.prefix(8))"
    }

    /// Updates all border labels when session count changes.
    func refreshBorderLabels() {
        for (sid, tracked) in sessions {
            tracked.borderWindow?.updateLabel(borderLabel(for: sid))
        }
    }

    /// Ordered list of sessions for display.
    var orderedSessions: [TrackedSession] {
        sessions.values.sorted { $0.sessionID < $1.sessionID }
    }
}
