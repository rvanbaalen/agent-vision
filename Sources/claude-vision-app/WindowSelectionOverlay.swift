import AppKit
import ClaudeVisionShared

/// Controller that manages window selection across all screens.
/// Polls NSEvent.mouseLocation via timer so tracking works on every monitor.
@MainActor
class WindowSelectionController {
    private var overlays: [WindowSelectionOverlay] = []
    private var pollTimer: Timer?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var windowRects: [(pid: pid_t, name: String?, frame: CGRect)] = []
    private var highlightedRect: CGRect?
    private var highlightedName: String?

    func begin() {
        // Create one overlay per screen
        for screen in NSScreen.screens {
            let overlay = WindowSelectionOverlay(screen: screen)
            overlays.append(overlay)
            overlay.orderFrontRegardless()
        }
        // Make the first overlay key so it can receive keyboard events
        overlays.first?.makeKeyAndOrderFront(nil)

        NSCursor.crosshair.push()
        refreshWindowList()

        // Poll mouse position — works across all monitors regardless of key window
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMouseMoved()
            }
        }

        // Monitor clicks and keyboard across the app
        let controller = self
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            MainActor.assumeIsolated { controller.handleClick() }
            return nil // consume
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                MainActor.assumeIsolated {
                    controller.end()
                    NotificationCenter.default.post(name: .selectionCancelled, object: nil)
                }
            }
            return nil // consume
        }
    }

    func end() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        NSCursor.pop()
        for overlay in overlays { overlay.orderOut(nil) }
        overlays.removeAll()
    }

    private func handleMouseMoved() {
        refreshWindowList()

        // NSEvent.mouseLocation is in AppKit coords (bottom-left origin, global)
        let appKitPoint = NSEvent.mouseLocation

        // Convert to Quartz coordinates (top-left origin) using the main screen height
        // In AppKit global coords, the main screen origin is at bottom-left
        // Quartz y = mainScreenHeight - appKitY
        let mainScreenHeight = NSScreen.screens[0].frame.height
        let quartzPoint = CGPoint(x: appKitPoint.x, y: mainScreenHeight - appKitPoint.y)

        // Find topmost window containing the cursor
        var found: (name: String?, frame: CGRect)?
        for w in windowRects {
            if w.frame.contains(quartzPoint) {
                found = (name: w.name, frame: w.frame)
                break // CGWindowList is front-to-back order
            }
        }

        highlightedRect = found?.frame
        highlightedName = found?.name

        // Update all overlays
        for overlay in overlays {
            overlay.updateHighlight(quartzRect: highlightedRect, name: highlightedName)
        }
    }

    private func handleClick() {
        guard let rect = highlightedRect else { return }

        let area = CaptureArea(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.width),
            height: Double(rect.height)
        )

        NotificationCenter.default.post(name: .areaSelected, object: area)
    }

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

            if pid == myPID { continue }
            if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 { continue }

            let name = info[kCGWindowOwnerName as String] as? String
            windowRects.append((pid: pid, name: name, frame: CGRect(x: wx, y: wy, width: ww, height: wh)))
        }
    }
}

/// Overlay window for a single screen — draws the highlight. Managed by WindowSelectionController.
class WindowSelectionOverlay: NSWindow {
    private var highlightView: WindowHighlightView!

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

        highlightView = WindowHighlightView(frame: screen.frame)
        highlightView.screenFrame = screen.frame
        contentView = highlightView
    }

    override var canBecomeKey: Bool { true }

    func updateHighlight(quartzRect: CGRect?, name: String?) {
        highlightView.updateHighlight(quartzRect: quartzRect, name: name)
    }
}

/// View that draws the window highlight on a single screen.
class WindowHighlightView: NSView {
    var screenFrame: NSRect = .zero
    private var highlightRect: CGRect? // Quartz coords
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
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateHighlight(quartzRect: CGRect?, name: String?) {
        highlightRect = quartzRect

        if let rect = quartzRect, let name = name {
            let viewRect = quartzToView(rect)

            // Only show label if the highlight intersects this screen
            if bounds.intersects(viewRect) {
                infoLabel.stringValue = " \(name)  \(Int(rect.width))\u{00d7}\(Int(rect.height)) "
                infoLabel.sizeToFit()
                infoLabel.frame.origin = NSPoint(
                    x: max(0, viewRect.minX - screenFrame.origin.x),
                    y: min(bounds.height - 20, viewRect.maxY - screenFrame.origin.y + 4)
                )
                infoLabel.isHidden = false
            } else {
                infoLabel.isHidden = true
            }
        } else {
            infoLabel.isHidden = true
        }

        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let rect = highlightRect else { return }

        let viewRect = quartzToView(rect)

        // Only draw if the highlight intersects this screen's view
        guard bounds.intersects(viewRect) else { return }

        // Clip to our bounds (window may span beyond this screen)
        let clipped = viewRect.intersection(bounds)

        // Clear the highlight area (punch through the dark overlay)
        NSColor.clear.setFill()
        NSBezierPath(rect: clipped).fill()

        // Draw highlight border
        let path = NSBezierPath(rect: clipped)
        NSColor(red: 0, green: 0.478, blue: 1, alpha: 0.3).setFill()
        path.fill()
        NSColor(red: 0, green: 0.478, blue: 1, alpha: 1).setStroke()
        path.lineWidth = 3
        path.stroke()
    }

    /// Convert Quartz (top-left origin, global) rect to this view's coordinate space.
    private func quartzToView(_ rect: CGRect) -> NSRect {
        // Main screen height is the reference for Quartz ↔ AppKit conversion
        let mainScreenHeight = NSScreen.screens[0].frame.height
        return NSRect(
            x: rect.origin.x,
            y: mainScreenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
