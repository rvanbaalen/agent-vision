import AppKit
import AgentVisionShared

/// Lightweight window selection — no full-screen overlay.
/// Shows a floating border highlight over the window under the cursor.
@MainActor
class WindowSelectionController {
    /// Click-through border window that highlights the window under the cursor.
    private var highlightWindow: NSWindow?
    private var pollTimer: Timer?
    private var globalClickMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    /// The Quartz-coordinate bounds of the currently highlighted window.
    private var currentRect: CGRect?
    /// The CGWindowID of the currently highlighted window.
    private var currentWindowNumber: UInt32?
    /// The owner name of the currently highlighted window.
    private var currentWindowOwner: String?

    func begin() {
        // Create the highlight border window — click-through, no background
        let border = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        border.level = .floating
        border.isOpaque = false
        border.backgroundColor = .clear
        border.ignoresMouseEvents = true
        border.hasShadow = false
        border.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let borderView = HighlightBorderView(frame: .zero)
        border.contentView = borderView

        highlightWindow = border
        NSCursor.crosshair.push()

        // Poll mouse position at 60fps
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }

        // Global monitors catch events even when our app isn't focused
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleClick() }
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { MainActor.assumeIsolated { self?.handleEscape() } }
        }
        // Local monitors for when our app is focused
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { MainActor.assumeIsolated { self?.handleEscape() } }
            return nil
        }
    }

    func end() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        NSCursor.pop()
        highlightWindow?.orderOut(nil)
        highlightWindow = nil
        currentRect = nil
    }

    private func tick() {
        let mouseAppKit = NSEvent.mouseLocation
        let mainHeight = NSScreen.screens[0].frame.height
        let mouseQuartz = CGPoint(x: mouseAppKit.x, y: mainHeight - mouseAppKit.y)

        // Find topmost window under cursor
        var hitRect: CGRect?
        var hitWindowNumber: UInt32?
        var hitWindowOwner: String?
        for w in getWindowList() {
            if w.frame.contains(mouseQuartz) {
                hitRect = w.frame
                hitWindowNumber = w.windowNumber
                hitWindowOwner = w.name
                break
            }
        }

        currentRect = hitRect
        currentWindowNumber = hitWindowNumber
        currentWindowOwner = hitWindowOwner

        if let qRect = hitRect {
            // Convert Quartz rect to AppKit screen coords
            let appKitRect = NSRect(
                x: qRect.origin.x,
                y: mainHeight - qRect.origin.y - qRect.height,
                width: qRect.width,
                height: qRect.height
            )
            highlightWindow?.setFrame(appKitRect, display: false)
            (highlightWindow?.contentView as? HighlightBorderView)?.frame = NSRect(origin: .zero, size: appKitRect.size)
            highlightWindow?.contentView?.needsDisplay = true
            highlightWindow?.orderFrontRegardless()
        } else {
            highlightWindow?.orderOut(nil)
        }
    }

    private func handleClick() {
        guard let rect = currentRect else { return }
        end()
        let area = CaptureArea(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.width),
            height: Double(rect.height),
            windowNumber: currentWindowNumber,
            windowOwner: currentWindowOwner
        )
        NotificationCenter.default.post(name: .areaSelected, object: area)
    }

    private func handleEscape() {
        end()
        NotificationCenter.default.post(name: .selectionCancelled, object: nil)
    }

    private func getWindowList() -> [(name: String?, frame: CGRect, windowNumber: UInt32)] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let myPID = ProcessInfo.processInfo.processIdentifier
        var results: [(name: String?, frame: CGRect, windowNumber: UInt32)] = []

        for info in list {
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowNum = info[kCGWindowNumber as String] as? UInt32,
                  let wx = boundsDict["X"] as? CGFloat,
                  let wy = boundsDict["Y"] as? CGFloat,
                  let ww = boundsDict["Width"] as? CGFloat,
                  let wh = boundsDict["Height"] as? CGFloat,
                  ww > 50, wh > 50 else { continue }

            if pid == myPID { continue }
            if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 { continue }

            let name = info[kCGWindowOwnerName as String] as? String
            results.append((name: name, frame: CGRect(x: wx, y: wy, width: ww, height: wh), windowNumber: windowNum))
        }
        return results
    }
}

/// Simple view that draws a blue border — nothing else.
class HighlightBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds.insetBy(dx: 2, dy: 2))
        NSColor(red: 0, green: 0.478, blue: 1, alpha: 1).setStroke()
        path.lineWidth = 4
        path.stroke()
    }
}
