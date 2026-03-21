import AppKit
import ClaudeVisionShared

class ActionFeedbackWindow: NSWindow {
    private var feedbackView: FeedbackView!

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        super.init(
            contentRect: screen.frame,
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

        feedbackView = FeedbackView(frame: screen.frame)
        contentView = feedbackView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func showRipple(at screenPoint: CGPoint) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let appKitY = screen.frame.height - screenPoint.y
        let viewPoint = NSPoint(x: screenPoint.x - frame.origin.x, y: appKitY - frame.origin.y)

        orderFront(nil)
        feedbackView.animateRipple(at: viewPoint)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.orderOut(nil)
        }
    }
}

class FeedbackView: NSView {
    private var rippleCenter: NSPoint?
    private var rippleProgress: CGFloat = 0
    private var animationTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func animateRipple(at point: NSPoint) {
        rippleCenter = point
        rippleProgress = 0

        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.rippleProgress += 1.0 / 15.0
            if self.rippleProgress >= 1.0 {
                timer.invalidate()
                self.rippleCenter = nil
            }
            self.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let center = rippleCenter else { return }

        let startSize: CGFloat = 20
        let endSize: CGFloat = 30
        let size = startSize + (endSize - startSize) * rippleProgress
        let alpha = 1.0 - rippleProgress

        let blue = NSColor(red: 0, green: 0.478, blue: 1, alpha: alpha * 0.6)
        let borderBlue = NSColor(red: 0, green: 0.478, blue: 1, alpha: alpha)

        let rect = NSRect(
            x: center.x - size / 2,
            y: center.y - size / 2,
            width: size,
            height: size
        )

        let path = NSBezierPath(ovalIn: rect)
        blue.setFill()
        path.fill()
        borderBlue.setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
