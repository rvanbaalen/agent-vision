import AppKit
import AgentVisionShared

/// Colored overlay that sits on the title bar of the tracked window and follows it.
class BorderWindow: NSWindow {
    private var overlayView: TitleBarOverlayView!
    private var trackingTimer: Timer?
    private let trackedWindowNumber: UInt32?

    static let barHeight: CGFloat = 22

    init(area: CaptureArea, sessionColor: SessionColor, sessionLabel: String) {
        self.trackedWindowNumber = area.windowNumber

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenHeight = screen.frame.height

        let frame = NSRect(
            x: CGFloat(area.x),
            y: screenHeight - CGFloat(area.y) - Self.barHeight,
            width: CGFloat(area.width),
            height: Self.barHeight
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
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        overlayView = TitleBarOverlayView(
            frame: NSRect(origin: .zero, size: frame.size),
            color: NSColor(red: sessionColor.red, green: sessionColor.green, blue: sessionColor.blue, alpha: 1),
            label: sessionLabel
        )
        contentView = overlayView

        // If tracking a specific window, poll its position
        if trackedWindowNumber != nil {
            startTracking()
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateLabel(_ newLabel: String) {
        overlayView.label = newLabel
        overlayView.needsDisplay = true
    }

    private func startTracking() {
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
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

            let newFrame = NSRect(
                x: wx,
                y: screenHeight - wy - Self.barHeight,
                width: ww,
                height: Self.barHeight
            )

            if frame != newFrame {
                setFrame(newFrame, display: true)
            }
            return
        }

        // Window not found — it may have been closed
        orderOut(nil)
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

}

class TitleBarOverlayView: NSView {
    let color: NSColor
    var label: String

    init(frame: NSRect, color: NSColor, label: String) {
        self.color = color
        self.label = label
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Semi-transparent colored bar
        color.withAlphaComponent(0.75).setFill()
        let barPath = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
        barPath.fill()

        // Label text
        let labelString = NSAttributedString(
            string: label,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
        )
        let textSize = labelString.size()
        let textX = bounds.width - textSize.width - 8
        let textY = (bounds.height - textSize.height) / 2
        labelString.draw(at: NSPoint(x: textX, y: textY))
    }
}
