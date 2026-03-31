import AppKit
import AgentVisionShared

extension AppDelegate {
    func setupMenuBar() {
        let mainMenu = NSMenu()

        // Agent Vision menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Agent Vision", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Agent Vision", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Session menu
        let sessionMenuItem = NSMenuItem()
        let sessionMenu = NSMenu(title: "Session")
        sessionMenuItem.submenu = sessionMenu
        mainMenu.addItem(sessionMenuItem)

        // Help menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Agent Vision Help", action: #selector(openHelp), keyEquivalent: "")
        helpMenu.addItem(withTitle: "View on Website", action: #selector(openWebsite), keyEquivalent: "")
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func showAbout() {
        AboutWindow.shared.showAbout()
    }

    @objc func checkUpdates() {
        AboutWindow.shared.showAbout()
        AboutWindow.shared.triggerUpdateCheck()
    }

    @objc func openHelp() {
        if let url = URL(string: "https://robinvanbaalen.nl/agent-vision") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func openWebsite() {
        if let url = URL(string: "https://robinvanbaalen.nl/agent-vision") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Session menu updates

extension AppDelegate {
    func rebuildSessionMenu() {
        guard let mainMenu = NSApp.mainMenu,
              mainMenu.items.count >= 2,
              let sessionMenu = mainMenu.items[1].submenu else { return }

        sessionMenu.removeAllItems()

        let header = NSMenuItem(title: "Active Sessions", action: nil, keyEquivalent: "")
        header.isEnabled = false
        sessionMenu.addItem(header)

        for tracked in sessionManager.orderedSessions {
            let color = SessionColors.color(forIndex: tracked.colorIndex)
            let prefix = String(tracked.sessionID.prefix(8))
            let dims: String
            if let area = tracked.area {
                dims = "\(Int(area.width))\u{00d7}\(Int(area.height))"
            } else {
                dims = "awaiting selection"
            }

            let item = NSMenuItem(title: "\(prefix) · \(dims)", action: nil, keyEquivalent: "")
            let dot = NSMutableAttributedString(string: "● ", attributes: [
                .foregroundColor: NSColor(red: color.red, green: color.green, blue: color.blue, alpha: 1),
                .font: NSFont.systemFont(ofSize: 12),
            ])
            dot.append(NSAttributedString(string: "\(prefix) · \(dims)", attributes: [
                .font: NSFont.systemFont(ofSize: 12),
            ]))
            item.attributedTitle = dot
            sessionMenu.addItem(item)
        }

        sessionMenu.addItem(.separator())

        let stopSelected = NSMenuItem(title: "Stop Selected Session", action: #selector(stopSelectedSession), keyEquivalent: "")
        stopSelected.target = self
        sessionMenu.addItem(stopSelected)

        let stopAll = NSMenuItem(title: "Stop All Sessions", action: #selector(stopAllSessions), keyEquivalent: "")
        stopAll.target = self
        sessionMenu.addItem(stopAll)
    }

    @objc func stopSelectedSession() {
        guard let sid = sessionManager.selectedSessionID else { return }
        sessionManager.stopSession(id: sid)
    }

    @objc func stopAllSessions() {
        sessionManager.stopAllSessions()
    }
}
