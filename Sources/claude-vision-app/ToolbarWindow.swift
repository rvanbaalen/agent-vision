import AppKit
import ClaudeVisionShared

class ToolbarWindow: NSPanel {
    private var selectButton: NSButton!

    init() {
        let toolbarWidth: CGFloat = 460
        let toolbarHeight: CGFloat = 52

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

    func updateSelectButtonTitle(_ title: String) {
        selectButton?.title = "Select Area  \(title)"
    }

    private func setupContent(toolbarWidth: CGFloat, toolbarHeight: CGFloat) {
        // Visual effect background
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: toolbarWidth, height: toolbarHeight))
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true

        // Title label
        let titleLabel = NSTextField(labelWithString: "Claude Vision")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        // Separator
        let separator = NSBox(frame: .zero)
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator

        // Select Area button — icon leading, label beside it
        let selectBtn = HoverButton(frame: .zero)
        selectBtn.translatesAutoresizingMaskIntoConstraints = false
        selectBtn.bezelStyle = .regularSquare
        selectBtn.isBordered = false
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        selectBtn.image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: "Select Area")?.withSymbolConfiguration(symbolConfig)
        selectBtn.imagePosition = .imageLeading
        selectBtn.imageScaling = .scaleNone
        selectBtn.title = "Select Area"
        selectBtn.font = .systemFont(ofSize: 12, weight: .medium)
        selectBtn.contentTintColor = .labelColor
        selectBtn.target = self
        selectBtn.action = #selector(selectAreaTapped)
        selectBtn.wantsLayer = true
        selectBtn.layer?.cornerRadius = 6
        let btnBg = NSColor.white.withAlphaComponent(0.08).cgColor
        selectBtn.layer?.backgroundColor = btnBg
        selectBtn.restingBackground = btnBg
        self.selectButton = selectBtn

        // Select Window button
        let windowBtn = HoverButton(frame: .zero)
        windowBtn.translatesAutoresizingMaskIntoConstraints = false
        windowBtn.bezelStyle = .regularSquare
        windowBtn.isBordered = false
        let windowSymbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        windowBtn.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Select Window")?.withSymbolConfiguration(windowSymbolConfig)
        windowBtn.imagePosition = .imageLeading
        windowBtn.imageScaling = .scaleNone
        windowBtn.title = "Select Window"
        windowBtn.font = .systemFont(ofSize: 12, weight: .medium)
        windowBtn.contentTintColor = .labelColor
        windowBtn.target = self
        windowBtn.action = #selector(selectWindowTapped)
        windowBtn.wantsLayer = true
        windowBtn.layer?.cornerRadius = 6
        windowBtn.layer?.backgroundColor = btnBg
        windowBtn.restingBackground = btnBg

        // Close button — plain NSButton, no padding cell
        let closeButton = NSButton(frame: .zero)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close")
        closeButton.imageScaling = .scaleProportionallyUpOrDown
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.contentTintColor = .tertiaryLabelColor

        visualEffect.addSubview(titleLabel)
        visualEffect.addSubview(separator)
        visualEffect.addSubview(selectBtn)
        visualEffect.addSubview(windowBtn)
        visualEffect.addSubview(closeButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),

            separator.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
            separator.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
            separator.heightAnchor.constraint(equalToConstant: 22),
            separator.widthAnchor.constraint(equalToConstant: 1),

            selectBtn.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 10),
            selectBtn.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),

            windowBtn.leadingAnchor.constraint(equalTo: selectBtn.trailingAnchor, constant: 6),
            windowBtn.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),

            closeButton.leadingAnchor.constraint(greaterThanOrEqualTo: windowBtn.trailingAnchor, constant: 10),
            closeButton.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -14),
            closeButton.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),
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

    @objc private func selectWindowTapped() {
        orderOut(nil)
        NotificationCenter.default.post(name: .beginWindowSelection, object: nil)
    }
}

// Button cell that adds internal padding around content
class PaddedButtonCell: NSButtonCell {
    var inset = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        return NSRect(
            x: rect.origin.x + inset.left,
            y: rect.origin.y + inset.bottom,
            width: rect.width - inset.left - inset.right,
            height: rect.height - inset.top - inset.bottom
        )
    }

    override func cellSize(forBounds rect: NSRect) -> NSSize {
        var size = super.cellSize(forBounds: rect)
        size.width += inset.left + inset.right
        size.height += inset.top + inset.bottom
        return size
    }
}

// Button with hover highlight and internal padding
class HoverButton: NSButton {
    private var trackingArea: NSTrackingArea?
    var restingBackground: CGColor?

    override class var cellClass: AnyClass? {
        get { PaddedButtonCell.self }
        set {}
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = restingBackground
    }
}

extension Notification.Name {
    static let beginAreaSelection = Notification.Name("beginAreaSelection")
    static let beginWindowSelection = Notification.Name("beginWindowSelection")
    static let areaSelected = Notification.Name("areaSelected")
    static let selectionCancelled = Notification.Name("selectionCancelled")
}
