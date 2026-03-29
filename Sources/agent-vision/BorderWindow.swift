import AppKit
import AgentVisionShared

class BorderWindow: NSWindow {
    init(area: CaptureArea) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenHeight = screen.frame.height

        let padding: CGFloat = 4
        let labelHeight: CGFloat = 18
        let frame = NSRect(
            x: CGFloat(area.x) - padding,
            y: screenHeight - CGFloat(area.y) - CGFloat(area.height) - padding,
            width: CGFloat(area.width) + padding * 2,
            height: CGFloat(area.height) + padding * 2 + labelHeight
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

        let borderView = BorderView(
            frame: NSRect(origin: .zero, size: frame.size),
            padding: padding,
            labelHeight: labelHeight
        )
        contentView = borderView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

class BorderView: NSView {
    let padding: CGFloat
    let labelHeight: CGFloat

    init(frame: NSRect, padding: CGFloat, labelHeight: CGFloat) {
        self.padding = padding
        self.labelHeight = labelHeight
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let blue = NSColor(red: 0, green: 0.478, blue: 1, alpha: 0.7)

        // Dashed border rectangle
        let borderRect = NSRect(
            x: padding,
            y: padding,
            width: bounds.width - padding * 2,
            height: bounds.height - padding * 2 - labelHeight
        )

        let path = NSBezierPath(rect: borderRect)
        path.lineWidth = 2
        let dashPattern: [CGFloat] = [6, 4]
        path.setLineDash(dashPattern, count: 2, phase: 0)
        blue.setStroke()
        path.stroke()

        // "Claude Vision" label
        let labelString = NSAttributedString(
            string: "Claude Vision",
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: blue,
                .backgroundColor: NSColor(red: 0, green: 0.478, blue: 1, alpha: 0.1),
            ]
        )
        let labelX = bounds.width - padding - labelString.size().width - 4
        let labelY = bounds.height - padding - labelHeight + 2
        labelString.draw(at: NSPoint(x: labelX, y: labelY))
    }
}
