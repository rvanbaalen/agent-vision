import AppKit
import AgentVisionShared

class ToolbarWindow: NSPanel {
    private var selectButton: NSButton!
    private var dropdownButton: NSButton!
    weak var sessionManager: SessionManager?

    init() {
        let toolbarWidth: CGFloat = 560
        let toolbarHeight: CGFloat = 52

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

    func refreshDropdown() {
        guard let sm = sessionManager, let sid = sm.selectedSessionID,
              let tracked = sm.sessions[sid] else {
            dropdownButton?.title = "No sessions"
            return
        }
        let dims: String
        if let area = tracked.area {
            dims = "\(Int(area.width))\u{00d7}\(Int(area.height))"
        } else {
            dims = "awaiting selection"
        }
        let prefix = String(sid.prefix(8))
        dropdownButton?.title = "\(prefix) · \(dims)"

        // Tint dropdown background to session color
        let color = SessionColors.color(forIndex: tracked.colorIndex)
        dropdownButton?.layer?.backgroundColor = NSColor(
            red: color.red, green: color.green, blue: color.blue, alpha: 0.15
        ).cgColor
    }

    private func setupContent(toolbarWidth: CGFloat, toolbarHeight: CGFloat) {
        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: toolbarWidth, height: toolbarHeight))
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true

        // Title button (clickable — opens About)
        let titleLabel = HoverButton(frame: .zero)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.bezelStyle = .regularSquare
        titleLabel.isBordered = false
        titleLabel.title = "Agent Vision"
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.contentTintColor = .labelColor
        titleLabel.target = self
        titleLabel.action = #selector(titleTapped)
        titleLabel.wantsLayer = true
        titleLabel.layer?.cornerRadius = 6
        titleLabel.restingBackground = nil

        // Separator 1
        let sep1 = NSBox(frame: .zero)
        sep1.translatesAutoresizingMaskIntoConstraints = false
        sep1.boxType = .separator

        // Session dropdown
        let dropdown = HoverButton(frame: .zero)
        dropdown.translatesAutoresizingMaskIntoConstraints = false
        dropdown.bezelStyle = .regularSquare
        dropdown.isBordered = false
        dropdown.title = "No sessions"
        dropdown.font = .systemFont(ofSize: 11, weight: .medium)
        dropdown.contentTintColor = .labelColor
        dropdown.target = self
        dropdown.action = #selector(dropdownTapped(_:))
        dropdown.wantsLayer = true
        dropdown.layer?.cornerRadius = 6
        let dropBg = NSColor.white.withAlphaComponent(0.08).cgColor
        dropdown.layer?.backgroundColor = dropBg
        dropdown.restingBackground = dropBg
        self.dropdownButton = dropdown

        // Separator 2
        let sep2 = NSBox(frame: .zero)
        sep2.translatesAutoresizingMaskIntoConstraints = false
        sep2.boxType = .separator

        // Select Area button
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

        // Close button
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
        visualEffect.addSubview(sep1)
        visualEffect.addSubview(dropdown)
        visualEffect.addSubview(sep2)
        visualEffect.addSubview(selectBtn)
        visualEffect.addSubview(windowBtn)
        visualEffect.addSubview(closeButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),

            sep1.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 10),
            sep1.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
            sep1.heightAnchor.constraint(equalToConstant: 22),
            sep1.widthAnchor.constraint(equalToConstant: 1),

            dropdown.leadingAnchor.constraint(equalTo: sep1.trailingAnchor, constant: 8),
            dropdown.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),

            sep2.leadingAnchor.constraint(equalTo: dropdown.trailingAnchor, constant: 8),
            sep2.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
            sep2.heightAnchor.constraint(equalToConstant: 22),
            sep2.widthAnchor.constraint(equalToConstant: 1),

            selectBtn.leadingAnchor.constraint(equalTo: sep2.trailingAnchor, constant: 8),
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
        guard let sm = sessionManager, let sid = sm.selectedSessionID else {
            NSApp.terminate(nil)
            return
        }
        sm.stopSession(id: sid)
    }

    @objc private func selectAreaTapped() {
        orderOut(nil)
        NotificationCenter.default.post(name: .beginAreaSelection, object: nil)
    }

    @objc private func selectWindowTapped() {
        orderOut(nil)
        NotificationCenter.default.post(name: .beginWindowSelection, object: nil)
    }

    @objc private func titleTapped() {
        AboutWindow.shared.showAbout()
    }

    @objc private func dropdownTapped(_ sender: NSButton) {
        guard let sm = sessionManager else { return }
        let menu = NSMenu()

        for tracked in sm.orderedSessions {
            let color = SessionColors.color(forIndex: tracked.colorIndex)
            let prefix = String(tracked.sessionID.prefix(8))
            let dims: String
            if let area = tracked.area {
                dims = "\(Int(area.width))\u{00d7}\(Int(area.height))"
            } else {
                dims = "awaiting selection"
            }

            // Session entry — click to select
            let item = NSMenuItem(title: "\(prefix) · \(dims)", action: #selector(selectSession(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tracked.sessionID

            let dot = NSMutableAttributedString(string: "● ", attributes: [
                .foregroundColor: NSColor(red: color.red, green: color.green, blue: color.blue, alpha: 1),
                .font: NSFont.systemFont(ofSize: 12),
            ])
            dot.append(NSAttributedString(string: "\(prefix) · \(dims)", attributes: [
                .font: NSFont.systemFont(ofSize: 12),
            ]))
            item.attributedTitle = dot

            if tracked.sessionID == sm.selectedSessionID {
                item.state = .on
            }

            // Submenu with Stop action for this session
            let submenu = NSMenu()
            let stopItem = NSMenuItem(title: "Stop Session", action: #selector(stopSession(_:)), keyEquivalent: "")
            stopItem.target = self
            stopItem.representedObject = tracked.sessionID
            submenu.addItem(stopItem)
            item.submenu = submenu

            menu.addItem(item)
        }

        if sm.sessions.count > 1 {
            menu.addItem(.separator())
            let stopAll = NSMenuItem(title: "Stop All Sessions", action: #selector(stopAllSessions), keyEquivalent: "")
            stopAll.target = self
            menu.addItem(stopAll)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @objc private func selectSession(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String else { return }
        sessionManager?.selectedSessionID = sid
        refreshDropdown()
    }

    @objc private func stopSession(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String else { return }
        sessionManager?.stopSession(id: sid)
    }

    @objc private func stopAllSessions() {
        sessionManager?.stopAllSessions()
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
