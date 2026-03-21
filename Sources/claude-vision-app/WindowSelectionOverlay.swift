import AppKit
import ClaudeVisionShared

class WindowSelectionOverlay: NSWindow {
    private var selectionView: WindowSelectionView!

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.3)
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces]

        selectionView = WindowSelectionView(frame: screen.frame)
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }

    func beginSelection() {
        makeKeyAndOrderFront(nil)
        NSCursor.crosshair.push()
    }

    func endSelection() {
        NSCursor.pop()
        orderOut(nil)
    }
}

class WindowSelectionView: NSView {
    /// Window info from CGWindowList — cached on mouse move.
    private var windowRects: [(pid: pid_t, name: String?, frame: CGRect)] = []
    /// Currently highlighted window rect in screen (Quartz) coordinates.
    private var highlightedRect: CGRect?
    /// Label showing window name / dimensions.
    private let infoLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)

        infoLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        infoLabel.textColor = .white
        infoLabel.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        infoLabel.isBezeled = false
        infoLabel.drawsBackground = true
        infoLabel.wantsLayer = true
        infoLabel.layer?.cornerRadius = 4
        infoLabel.isHidden = true
        addSubview(infoLabel)

        // Cache window list once at start
        refreshWindowList()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Window List

    private func refreshWindowList() {
        windowRects = []
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        let myPID = ProcessInfo.processInfo.processIdentifier

        for info in list {
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let wx = boundsDict["X"] as? CGFloat,
                  let wy = boundsDict["Y"] as? CGFloat,
                  let ww = boundsDict["Width"] as? CGFloat,
                  let wh = boundsDict["Height"] as? CGFloat,
                  ww > 50, wh > 50 else { continue }

            // Skip our own windows (toolbar, overlay, border)
            if pid == myPID { continue }

            // Skip windows with layer 0 (some system elements)
            if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 { continue }

            let name = info[kCGWindowOwnerName as String] as? String
            windowRects.append((pid: pid, name: name, frame: CGRect(x: wx, y: wy, width: ww, height: wh)))
        }
    }

    // MARK: - Mouse Tracking

    override func mouseMoved(with event: NSEvent) {
        let screenPoint = NSEvent.mouseLocation
        // Convert to Quartz coordinates (top-left origin)
        guard let screenHeight = window?.screen?.frame.height ?? NSScreen.main?.frame.height else { return }
        let quartzPoint = CGPoint(x: screenPoint.x, y: screenHeight - screenPoint.y)

        // Refresh window list on each move to catch changes
        refreshWindowList()

        // Find topmost window containing the cursor
        var found: (name: String?, frame: CGRect)?
        for w in windowRects {
            if w.frame.contains(quartzPoint) {
                found = (name: w.name, frame: w.frame)
                break // CGWindowList is front-to-back order
            }
        }

        if let hit = found {
            highlightedRect = hit.frame
            let label = hit.name ?? "Unknown"
            infoLabel.stringValue = " \(label)  \(Int(hit.frame.width))\u{00d7}\(Int(hit.frame.height)) "
            infoLabel.sizeToFit()

            // Position label above the highlighted window (in view coords)
            let viewRect = quartzToView(hit.frame, screenHeight: screenHeight)
            infoLabel.frame.origin = NSPoint(x: viewRect.minX, y: viewRect.maxY + 4)
            infoLabel.isHidden = false
        } else {
            highlightedRect = nil
            infoLabel.isHidden = true
        }

        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let rect = highlightedRect else { return }

        // rect is already in Quartz (top-left) coordinates — same as CaptureArea
        let area = CaptureArea(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.width),
            height: Double(rect.height)
        )

        NotificationCenter.default.post(name: .areaSelected, object: area)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            highlightedRect = nil
            infoLabel.isHidden = true
            needsDisplay = true
            (window as? WindowSelectionOverlay)?.endSelection()
            NotificationCenter.default.post(name: .selectionCancelled, object: nil)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Track mouse movement across the entire view
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let rect = highlightedRect,
              let screenHeight = window?.screen?.frame.height ?? NSScreen.main?.frame.height else { return }

        let viewRect = quartzToView(rect, screenHeight: screenHeight)

        // Clear the highlight area (punch through the dark overlay)
        NSColor.clear.setFill()
        NSBezierPath(rect: viewRect).fill()

        // Draw highlight border
        let path = NSBezierPath(rect: viewRect)
        NSColor(red: 0, green: 0.478, blue: 1, alpha: 0.3).setFill()
        path.fill()
        NSColor(red: 0, green: 0.478, blue: 1, alpha: 1).setStroke()
        path.lineWidth = 3
        path.stroke()
    }

    // MARK: - Coordinate Conversion

    /// Convert Quartz (top-left origin) rect to NSView (bottom-left origin) rect.
    private func quartzToView(_ rect: CGRect, screenHeight: CGFloat) -> NSRect {
        return NSRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
