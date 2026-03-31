import AppKit
import AgentVisionShared

/// Small colored pill label that floats on the title bar of the tracked window.
class BorderWindow: NSWindow {
    private var pillView: PillView!
    private var trackingTimer: Timer?
    private let trackedWindowNumber: UInt32?

    /// Inset from the window's top-right corner to avoid clipping the border radius.
    private static let insetX: CGFloat = 6
    private static let insetY: CGFloat = 4

    init(area: CaptureArea, sessionColor sc: SessionColor, sessionLabel: String) {
        self.trackedWindowNumber = area.windowNumber

        let color = NSColor(red: sc.red, green: sc.green, blue: sc.blue, alpha: 1)
        let pillSize = PillView.measure(text: sessionLabel)

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenHeight = screen.frame.height

        let frame = NSRect(
            x: CGFloat(area.x) + CGFloat(area.width) - pillSize.width - Self.insetX,
            y: screenHeight - CGFloat(area.y) - pillSize.height - Self.insetY,
            width: pillSize.width,
            height: pillSize.height
        )

        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        pillView = PillView(frame: NSRect(origin: .zero, size: frame.size), color: color, text: sessionLabel)
        contentView = pillView

        if trackedWindowNumber != nil {
            startTracking()
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateLabel(_ newLabel: String) {
        pillView.text = newLabel
        pillView.needsDisplay = true
    }

    // MARK: - Window position tracking

    private func startTracking() {
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updatePosition()
            }
        }
    }

    private func updatePosition() {
        guard let windowNum = trackedWindowNumber else { return }

        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return }

        for info in list {
            guard let num = info[kCGWindowNumber as String] as? UInt32,
                  num == windowNum,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let wx = boundsDict["X"] as? CGFloat,
                  let wy = boundsDict["Y"] as? CGFloat,
                  let ww = boundsDict["Width"] as? CGFloat else { continue }

            let screen = NSScreen.main ?? NSScreen.screens[0]
            let screenHeight = screen.frame.height
            let pillWidth = frame.width
            let pillHeight = frame.height

            let newFrame = NSRect(
                x: wx + ww - pillWidth - Self.insetX,
                y: screenHeight - wy - pillHeight - Self.insetY,
                width: pillWidth,
                height: pillHeight
            )

            if frame != newFrame {
                setFrame(newFrame, display: false)
            }
            return
        }

        // Window not found — it may have been closed
        orderOut(nil)
        stopTracking()
    }

    func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }
}

/// Custom-drawn pill: colored background with centered white text.
/// Uses CoreGraphics drawing for pixel-perfect alignment.
class PillView: NSView {
    let color: NSColor
    var text: String

    private static let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
    private static let paddingH: CGFloat = 8
    private static let paddingV: CGFloat = 3

    init(frame: NSRect, color: NSColor, text: String) {
        self.color = color
        self.text = text
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    static func measure(text: String) -> NSSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (text as NSString).size(withAttributes: attrs)
        return NSSize(
            width: ceil(textSize.width) + paddingH * 2,
            height: ceil(textSize.height) + paddingV * 2
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Pill background
        let pillPath = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        color.withAlphaComponent(0.8).setFill()
        pillPath.fill()

        // Centered text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor.white,
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let textX = (bounds.width - textSize.width) / 2
        let textY = (bounds.height - textSize.height) / 2
        (text as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
    }
}
