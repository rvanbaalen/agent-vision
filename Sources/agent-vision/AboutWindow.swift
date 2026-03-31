import AppKit
import AgentVisionShared

@MainActor
class AboutWindow {
    static let shared = AboutWindow()

    private var window: NSPanel?
    private var updateLabel: NSTextField?

    func showAbout() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "About Agent Vision"
        panel.isFloatingPanel = true
        panel.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 320))

        // App icon
        let iconView = NSImageView(frame: NSRect(x: 118, y: 230, width: 64, height: 64))
        if let appIcon = NSImage(named: NSImage.applicationIconName) {
            iconView.image = appIcon
        }
        content.addSubview(iconView)

        // App name
        let nameLabel = NSTextField(labelWithString: "Agent Vision")
        nameLabel.frame = NSRect(x: 0, y: 200, width: 300, height: 24)
        nameLabel.alignment = .center
        nameLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        content.addSubview(nameLabel)

        // Version
        let versionLabel = NSTextField(labelWithString: "Version \(AgentVisionVersion.current)")
        versionLabel.frame = NSRect(x: 0, y: 178, width: 300, height: 18)
        versionLabel.alignment = .center
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        content.addSubview(versionLabel)

        // Author
        let authorLabel = NSTextField(labelWithString: "by Robin van Baalen")
        authorLabel.frame = NSRect(x: 0, y: 148, width: 300, height: 18)
        authorLabel.alignment = .center
        authorLabel.font = .systemFont(ofSize: 12)
        authorLabel.textColor = .secondaryLabelColor
        content.addSubview(authorLabel)

        // Website link
        let linkButton = NSButton(frame: NSRect(x: 50, y: 122, width: 200, height: 20))
        linkButton.title = "robinvanbaalen.nl/agent-vision"
        linkButton.bezelStyle = .inline
        linkButton.isBordered = false
        linkButton.font = .systemFont(ofSize: 12)
        linkButton.contentTintColor = .linkColor
        linkButton.target = self
        linkButton.action = #selector(openWebsite)
        content.addSubview(linkButton)

        // Separator
        let separator = NSBox(frame: NSRect(x: 20, y: 108, width: 260, height: 1))
        separator.boxType = .separator
        content.addSubview(separator)

        // Update status
        let updateStatus = NSTextField(labelWithString: "Checking for updates…")
        updateStatus.frame = NSRect(x: 0, y: 78, width: 300, height: 18)
        updateStatus.alignment = .center
        updateStatus.font = .systemFont(ofSize: 11)
        updateStatus.textColor = .secondaryLabelColor
        content.addSubview(updateStatus)
        self.updateLabel = updateStatus

        panel.contentView = content
        panel.makeKeyAndOrderFront(nil)
        self.window = panel

        triggerUpdateCheck()
    }

    func triggerUpdateCheck() {
        updateLabel?.stringValue = "Checking for updates…"
        updateLabel?.textColor = .secondaryLabelColor

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = self?.performUpdateCheck()
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .upToDate:
                    self.updateLabel?.stringValue = "✓ Up to date"
                    self.updateLabel?.textColor = .systemGreen
                case .updateAvailable(let version):
                    self.updateLabel?.stringValue = "Update available: v\(version)\nbrew upgrade agent-vision"
                    self.updateLabel?.textColor = .systemOrange
                    self.updateLabel?.maximumNumberOfLines = 2
                case .failed, .none:
                    self.updateLabel?.stringValue = "Could not check for updates"
                    self.updateLabel?.textColor = .secondaryLabelColor
                }
            }
        }
    }

    private enum UpdateResult {
        case upToDate
        case updateAvailable(String)
        case failed
    }

    private nonisolated func performUpdateCheck() -> UpdateResult {
        let urlString = "https://api.github.com/repos/rvanbaalen/agent-vision/releases/latest"
        guard let url = URL(string: urlString) else { return .failed }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: UpdateResult = .failed

        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }

            let remote = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let local = AgentVisionVersion.current

            if remote != local, remote > local {
                result = .updateAvailable(remote)
            } else {
                result = .upToDate
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 5)
        return result
    }

    @objc private func openWebsite() {
        if let url = URL(string: "https://robinvanbaalen.nl/agent-vision") {
            NSWorkspace.shared.open(url)
        }
    }
}
