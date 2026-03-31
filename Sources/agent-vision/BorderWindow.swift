import AppKit
import AgentVisionShared

class BorderWindow: NSWindow {
    private var borderView: BorderView!

    init(area: CaptureArea, sessionColor: SessionColor, sessionLabel: String) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenHeight = screen.frame.height

        let padding: CGFloat = 4
        let labelHeight: CGFloat = 18

        // Check if label above the border would extend beyond the screen top
        let topEdgeInAppKit = screenHeight - CGFloat(area.y) + padding + labelHeight
        let labelOnTop = topEdgeInAppKit <= screenHeight

        let frame: NSRect
        if labelOnTop {
            frame = NSRect(
                x: CGFloat(area.x) - padding,
                y: screenHeight - CGFloat(area.y) - CGFloat(area.height) - padding,
                width: CGFloat(area.width) + padding * 2,
                height: CGFloat(area.height) + padding * 2 + labelHeight
            )
        } else {
            // Label goes below the border
            frame = NSRect(
                x: CGFloat(area.x) - padding,
                y: screenHeight - CGFloat(area.y) - CGFloat(area.height) - padding - labelHeight,
                width: CGFloat(area.width) + padding * 2,
                height: CGFloat(area.height) + padding * 2 + labelHeight
            )
        }

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

        borderView = BorderView(
            frame: NSRect(origin: .zero, size: frame.size),
            padding: padding,
            labelHeight: labelHeight,
            labelOnTop: labelOnTop,
            color: NSColor(red: sessionColor.red, green: sessionColor.green, blue: sessionColor.blue, alpha: 0.7),
            label: sessionLabel
        )
        contentView = borderView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateLabel(_ newLabel: String) {
        borderView.label = newLabel
        borderView.needsDisplay = true
    }
}

class BorderView: NSView {
    let padding: CGFloat
    let labelHeight: CGFloat
    let labelOnTop: Bool
    let color: NSColor
    var label: String

    init(frame: NSRect, padding: CGFloat, labelHeight: CGFloat, labelOnTop: Bool, color: NSColor, label: String) {
        self.padding = padding
        self.labelHeight = labelHeight
        self.labelOnTop = labelOnTop
        self.color = color
        self.label = label
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let borderY: CGFloat
        if labelOnTop {
            borderY = padding
        } else {
            borderY = padding + labelHeight
        }

        // Dashed border rectangle
        let borderRect = NSRect(
            x: padding,
            y: borderY,
            width: bounds.width - padding * 2,
            height: bounds.height - padding * 2 - labelHeight
        )

        let path = NSBezierPath(rect: borderRect)
        path.lineWidth = 2
        let dashPattern: [CGFloat] = [6, 4]
        path.setLineDash(dashPattern, count: 2, phase: 0)
        color.setStroke()
        path.stroke()

        // Label
        let labelString = NSAttributedString(
            string: label,
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: color,
                .backgroundColor: color.withAlphaComponent(0.15),
            ]
        )

        let labelX = bounds.width - padding - labelString.size().width - 4
        let labelY: CGFloat
        if labelOnTop {
            labelY = bounds.height - padding - labelHeight + 2
        } else {
            labelY = padding + 2
        }
        labelString.draw(at: NSPoint(x: labelX, y: labelY))
    }
}
