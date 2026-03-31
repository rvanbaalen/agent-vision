import AppKit
import AgentVisionShared

/// Small colored label that floats on the title bar of the tracked window.
class BorderWindow: NSWindow {
    private var labelField: NSTextField!
    private var displayLink: CVDisplayLink?
    private let trackedWindowNumber: UInt32?
    private let sessionColor: NSColor

    /// Inset from the window's top-right corner to avoid clipping the border radius.
    private static let insetX: CGFloat = 6
    private static let insetY: CGFloat = 4

    init(area: CaptureArea, sessionColor sc: SessionColor, sessionLabel: String) {
        self.trackedWindowNumber = area.windowNumber
        self.sessionColor = NSColor(red: sc.red, green: sc.green, blue: sc.blue, alpha: 1)

        // Measure label to size the window exactly
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (sessionLabel as NSString).size(withAttributes: attrs)
        let paddingH: CGFloat = 8
        let paddingV: CGFloat = 3
        let labelWidth = textSize.width + paddingH * 2
        let labelHeight = textSize.height + paddingV * 2

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let screenHeight = screen.frame.height

        // Position at the top-right of the area, inset to avoid border radius
        let frame = NSRect(
            x: CGFloat(area.x) + CGFloat(area.width) - labelWidth - Self.insetX,
            y: screenHeight - CGFloat(area.y) - labelHeight - Self.insetY,
            width: labelWidth,
            height: labelHeight
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

        let bg = NSView(frame: NSRect(origin: .zero, size: frame.size))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = sessionColor.withAlphaComponent(0.8).cgColor
        bg.layer?.cornerRadius = (labelHeight / 2).rounded(.down)
        bg.layer?.masksToBounds = true

        labelField = NSTextField(labelWithString: sessionLabel)
        labelField.font = font
        labelField.textColor = .white
        labelField.alignment = .center
        labelField.frame = NSRect(x: 0, y: 0, width: labelWidth, height: labelHeight)

        bg.addSubview(labelField)
        contentView = bg

        if trackedWindowNumber != nil {
            startDisplayLink()
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateLabel(_ newLabel: String) {
        labelField.stringValue = newLabel
    }

    // MARK: - CVDisplayLink tracking

    private func startDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { (_, _, _, _, _, userInfo) -> CVReturn in
            guard let userInfo else { return kCVReturnSuccess }
            let window = Unmanaged<BorderWindow>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    window.updatePosition()
                }
            }
            return kCVReturnSuccess
        }, selfPtr)

        CVDisplayLinkStart(link)
        self.displayLink = link
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
            let labelWidth = frame.width
            let labelHeight = frame.height

            let newFrame = NSRect(
                x: wx + ww - labelWidth - Self.insetX,
                y: screenHeight - wy - labelHeight - Self.insetY,
                width: labelWidth,
                height: labelHeight
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
        if let link = displayLink {
            CVDisplayLinkStop(link)
            displayLink = nil
        }
    }
}
