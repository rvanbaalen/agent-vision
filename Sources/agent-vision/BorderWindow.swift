import AppKit
import AgentVisionShared

/// Thin colored overlay that sits on the title bar of the selected area.
class BorderWindow: NSWindow {
    private var overlayView: TitleBarOverlayView!

    static let barHeight: CGFloat = 22

    init(area: CaptureArea, sessionColor: SessionColor, sessionLabel: String) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenHeight = screen.frame.height

        // Position at the top edge of the selected area (where the title bar is)
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
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateLabel(_ newLabel: String) {
        overlayView.label = newLabel
        overlayView.needsDisplay = true
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
