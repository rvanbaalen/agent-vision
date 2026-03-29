import AppKit
import AgentVisionShared

class SelectionOverlay: NSWindow {
    private var selectionView: SelectionView!

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

        selectionView = SelectionView(frame: screen.frame)
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

class SelectionView: NSView {
    private var startPoint: NSPoint?
    private var currentRect: NSRect?
    private let sizeLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)

        sizeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        sizeLabel.textColor = .white
        sizeLabel.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        sizeLabel.isBezeled = false
        sizeLabel.drawsBackground = true
        sizeLabel.wantsLayer = true
        sizeLabel.layer?.cornerRadius = 4
        sizeLabel.isHidden = true
        addSubview(sizeLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = nil
        sizeLabel.isHidden = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)

        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let w = abs(current.x - start.x)
        let h = abs(current.y - start.y)

        currentRect = NSRect(x: x, y: y, width: w, height: h)

        sizeLabel.stringValue = " \(Int(w)) \u{00d7} \(Int(h)) "
        sizeLabel.sizeToFit()
        sizeLabel.frame.origin = NSPoint(x: x, y: y + h + 4)

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = currentRect, rect.width > 10, rect.height > 10 else {
            // Too small — cancel
            startPoint = nil
            currentRect = nil
            sizeLabel.isHidden = true
            needsDisplay = true
            return
        }

        // Convert from view coordinates to screen coordinates
        // NSView coordinates are bottom-left origin
        // CGWindowListCreateImage uses top-left origin (Quartz coordinates)
        let screenFrame = window?.screen?.frame ?? NSScreen.main!.frame
        let screenRect = NSRect(
            x: rect.origin.x + screenFrame.origin.x,
            y: screenFrame.height - rect.origin.y - rect.height + screenFrame.origin.y,
            width: rect.width,
            height: rect.height
        )

        let area = CaptureArea(
            x: Double(screenRect.origin.x),
            y: Double(screenRect.origin.y),
            width: Double(screenRect.width),
            height: Double(screenRect.height)
        )

        NotificationCenter.default.post(name: .areaSelected, object: area)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            startPoint = nil
            currentRect = nil
            sizeLabel.isHidden = true
            needsDisplay = true
            (window as? SelectionOverlay)?.endSelection()
            NotificationCenter.default.post(name: .selectionCancelled, object: nil)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let rect = currentRect else { return }

        // Draw selection rectangle
        let path = NSBezierPath(rect: rect)
        NSColor(red: 0, green: 0.478, blue: 1, alpha: 0.15).setFill()
        path.fill()
        NSColor(red: 0, green: 0.478, blue: 1, alpha: 1).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
