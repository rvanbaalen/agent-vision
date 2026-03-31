import Foundation

public enum Config {
    public static let stateDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".agent-vision")
    public static let sessionsDirectory = stateDirectory.appendingPathComponent("sessions")
    public static let guiPidFilePath = stateDirectory.appendingPathComponent("gui.pid")

    // MARK: - Session Paths

    public static func sessionDirectory(for sessionID: String) -> URL {
        sessionsDirectory.appendingPathComponent(sessionID)
    }

    public static func stateFilePath(for sessionID: String) -> URL {
        sessionDirectory(for: sessionID).appendingPathComponent("state.json")
    }

    public static func elementsFilePath(for sessionID: String) -> URL {
        sessionDirectory(for: sessionID).appendingPathComponent("elements.json")
    }

    public static func actionFilePath(for sessionID: String) -> URL {
        sessionDirectory(for: sessionID).appendingPathComponent("action.json")
    }

    public static func actionResultFilePath(for sessionID: String) -> URL {
        sessionDirectory(for: sessionID).appendingPathComponent("action-result.json")
    }

    // MARK: - Session Validation

    public static func isValidSessionID(_ id: String) -> Bool {
        // UUID format: 8-4-4-4-12 hex chars
        let parts = id.split(separator: "-")
        guard parts.count == 5,
              parts[0].count == 8, parts[1].count == 4, parts[2].count == 4,
              parts[3].count == 4, parts[4].count == 12 else { return false }
        let hexChars = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return parts.allSatisfy { $0.unicodeScalars.allSatisfy { hexChars.contains($0) } }
    }

    // MARK: - Stale Cleanup

    /// Remove session directories whose PID is dead and are older than 24 hours.
    public static func cleanStaleSessions() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: sessionsDirectory, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)

        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: [.creationDateKey]),
                  let created = values.creationDate,
                  created < cutoff else { continue }

            // Check if the session's PID is still alive
            let statePath = entry.appendingPathComponent("state.json")
            if let data = try? Data(contentsOf: statePath),
               let state = try? JSONDecoder().decode(AppState.self, from: data),
               StateFile.isProcessRunning(pid: state.pid) {
                continue // still alive, don't clean
            }

            try? fm.removeItem(at: entry)
        }
    }
}
