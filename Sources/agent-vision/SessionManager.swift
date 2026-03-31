import AppKit
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

        // Auto-switch to newest session
        selectedSessionID = id
        onSessionsChanged?()
    }

    private func removeSession(id: String) {
        NSLog("[agent-vision] SessionManager: removing session \(id)")
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
