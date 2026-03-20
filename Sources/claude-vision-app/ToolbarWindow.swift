import AppKit
import ClaudeVisionShared

class ToolbarWindow: NSPanel {
    init() {
        let toolbarWidth: CGFloat = 180
        let toolbarHeight: CGFloat = 60

        // Position at bottom center of main screen
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - toolbarWidth / 2
        let y = screenFrame.minY + 20

        let contentRect = NSRect(x: x, y: y, width: toolbarWidth, height: toolbarHeight)

        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear

        setupContent(toolbarWidth: toolbarWidth, toolbarHeight: toolbarHeight)
    }

    private func setupContent(toolbarWidth: CGFloat, toolbarHeight: CGFloat) {
        // Visual effect background
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: toolbarWidth, height: toolbarHeight))
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 14
        visualEffect.layer?.masksToBounds = true

        // Close button
        let closeButton = NSButton(frame: .zero)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .circular
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.imageScaling = .scaleProportionallyUpOrDown
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.contentTintColor = .secondaryLabelColor

        // Select Area button
        let selectButton = NSButton(frame: .zero)
        selectButton.translatesAutoresizingMaskIntoConstraints = false
        selectButton.bezelStyle = .regularSquare
        selectButton.isBordered = false
        selectButton.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "Select Area")
        selectButton.imagePosition = .imageAbove
        selectButton.imageScaling = .scaleProportionallyUpOrDown
        selectButton.title = "Select Area"
        selectButton.font = .systemFont(ofSize: 10)
        selectButton.contentTintColor = .labelColor
        selectButton.target = self
        selectButton.action = #selector(selectAreaTapped)

        visualEffect.addSubview(closeButton)
        visualEffect.addSubview(selectButton)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 12),
            closeButton.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),

            selectButton.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor, constant: 12),
            selectButton.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
            selectButton.widthAnchor.constraint(equalToConstant: 80),
            selectButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        contentView = visualEffect
    }

    func showToolbar() {
        makeKeyAndOrderFront(nil)
    }

    @objc private func closeTapped() {
        StateFile.delete(at: Config.stateFilePath)
        NSApp.terminate(nil)
    }

    @objc private func selectAreaTapped() {
        orderOut(nil)
        NotificationCenter.default.post(name: .beginAreaSelection, object: nil)
    }
}

extension Notification.Name {
    static let beginAreaSelection = Notification.Name("beginAreaSelection")
    static let areaSelected = Notification.Name("areaSelected")
    static let selectionCancelled = Notification.Name("selectionCancelled")
}
