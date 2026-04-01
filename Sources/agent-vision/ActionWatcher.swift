import AppKit
import AgentVisionShared
import CoreGraphics
import ApplicationServices

@MainActor
class ActionWatcher {
    private var timer: Timer?
    private var onFeedback: ((ActionRequest, CaptureArea) -> Void)?
    private let sessionID: String
    private var isProcessingAction = false

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func start(onFeedback: @escaping (ActionRequest, CaptureArea) -> Void) {
        self.onFeedback = onFeedback
        NSLog("[agent-vision] ActionWatcher starting polling timer (0.1s)")
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForAction()
            }
        }
    }

    func stop() {
        NSLog("[agent-vision] ActionWatcher stopping")
        timer?.invalidate()
        timer = nil
    }

    private func checkForAction() {
        let actionPath = Config.actionFilePath(for: sessionID)
        let resultPath = Config.actionResultFilePath(for: sessionID)
        let sessionDir = Config.sessionDirectory(for: sessionID)
        guard FileManager.default.fileExists(atPath: actionPath.path) else { return }

        // Prevent re-entrant processing if a previous action is still running
        guard !isProcessingAction else {
            NSLog("[agent-vision] checkForAction skipped — still processing previous action")
            return
        }
        isProcessingAction = true

        let startTime = CFAbsoluteTimeGetCurrent()

        let action: ActionRequest
        let area: CaptureArea
        var focusTimeout: TimeInterval = 120 // Default 2 minutes
        do {
            // Read focusTimeout from raw JSON before decoding ActionRequest
            let rawData = try Data(contentsOf: actionPath)
            if let json = try? JSONSerialization.jsonObject(with: rawData) as? [String: Any],
               let timeout = json["focusTimeout"] as? Int {
                focusTimeout = TimeInterval(timeout)
            }

            action = try ActionFile.readAction(from: actionPath)
            NSLog("[agent-vision] Action received: \(action)")

            // Delete action file immediately after reading to prevent race condition:
            // if the CLI times out and sends a new action while we're still processing,
            // we must not delete the new action file when we finish the old one.
            ActionFile.delete(at: actionPath)

            guard let state = try StateFile.read(from: Config.stateFilePath(for: sessionID)),
                  let a = state.area else {
                NSLog("[agent-vision] No area selected — rejecting action")
                let result = ActionResult(success: false, message: "No area selected")
                try? ActionFile.writeResult(result, to: resultPath, createDirectory: sessionDir)
                isProcessingAction = false
                return
            }
            area = a

            guard AXIsProcessTrusted() else {
                NSLog("[agent-vision] Accessibility permission not granted")
                let result = ActionResult(success: false, message: "Error: Accessibility permission required. Enable it in System Settings > Privacy & Security > Accessibility.")
                try? ActionFile.writeResult(result, to: resultPath, createDirectory: sessionDir)
                isProcessingAction = false
                return
            }
        } catch {
            NSLog("[agent-vision] Failed to read action: \(error)")
            ActionFile.delete(at: actionPath)
            isProcessingAction = false
            return
        }

        // Element-based actions involve heavy AX tree walks — run on background thread
        // to prevent GUI freezes (which cause spindump and unresponsiveness).
        if case .clickElement(let index) = action {
            NSLog("[agent-vision] clickElement index=\(index)")
            let elementsPath = Config.elementsFilePath(for: sessionID)
            do {
                guard let scan = try ElementStore.read(from: elementsPath),
                      let el = ElementStore.lookup(index: index, in: scan) else {
                    NSLog("[agent-vision] Element \(index) not found in scan")
                    let result = ActionResult(success: false, message: "Element \(index) not found. Run 'agent-vision elements' first.")
                    try? ActionFile.writeResult(result, to: resultPath, createDirectory: sessionDir)
                    isProcessingAction = false
                    return
                }
                let capturedArea = area
                nonisolated(unsafe) let wself = self
                DispatchQueue.global(qos: .userInitiated).async { [weak wself] in
                    let actionResult: ActionResult
                    do {
                        try ElementAction.press(element: el, area: capturedArea)
                        NSLog("[agent-vision] clickElement success: \(el.displayLabel)")
                        actionResult = ActionResult(success: true, message: "Clicked \(el.displayLabel) (focus-free)")
                    } catch {
                        NSLog("[agent-vision] clickElement FAILED: \(error)")
                        actionResult = ActionResult(success: false, message: "\(error)")
                    }
                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    if elapsed > 0.5 {
                        NSLog("[agent-vision] WARNING: clickElement took \(String(format: "%.2f", elapsed))s")
                    }
                    try? ActionFile.writeResult(actionResult, to: resultPath, createDirectory: sessionDir)
                    DispatchQueue.main.async { [weak wself] in
                        wself?.isProcessingAction = false
                    }
                }
            } catch {
                NSLog("[agent-vision] Failed to read element scan: \(error)")
                isProcessingAction = false
            }
            return
        }

        if case .typeElement(let text, let index) = action {
            NSLog("[agent-vision] typeElement index=\(index) text=\"\(text.prefix(50))\"")
            let elementsPath = Config.elementsFilePath(for: sessionID)
            do {
                guard let scan = try ElementStore.read(from: elementsPath),
                      let el = ElementStore.lookup(index: index, in: scan) else {
                    NSLog("[agent-vision] Element \(index) not found in scan")
                    let result = ActionResult(success: false, message: "Element \(index) not found. Run 'agent-vision elements' first.")
                    try? ActionFile.writeResult(result, to: resultPath, createDirectory: sessionDir)
                    isProcessingAction = false
                    return
                }
                let capturedArea = area
                nonisolated(unsafe) let wself = self
                DispatchQueue.global(qos: .userInitiated).async { [weak wself] in
                    let actionResult: ActionResult
                    do {
                        try ElementAction.setText(text, element: el, area: capturedArea)
                        NSLog("[agent-vision] typeElement success: \(el.displayLabel)")
                        actionResult = ActionResult(success: true, message: "Typed into \(el.displayLabel) (focus-free)")
                    } catch {
                        NSLog("[agent-vision] typeElement FAILED: \(error)")
                        actionResult = ActionResult(success: false, message: "\(error)")
                    }
                    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                    if elapsed > 0.5 {
                        NSLog("[agent-vision] WARNING: typeElement took \(String(format: "%.2f", elapsed))s")
                    }
                    try? ActionFile.writeResult(actionResult, to: resultPath, createDirectory: sessionDir)
                    DispatchQueue.main.async { [weak wself] in
                        wself?.isProcessingAction = false
                    }
                }
            } catch {
                NSLog("[agent-vision] Failed to read element scan: \(error)")
                isProcessingAction = false
            }
            return
        }

        if case .discoverElements = action {
            NSLog("[agent-vision] discoverElements — starting element discovery")
            let capturedArea = area
            let sid = sessionID
            nonisolated(unsafe) let weakSelf = self
            DispatchQueue.global(qos: .userInitiated).async { [weak weakSelf] in
                let scanResult: ElementScanResult
                // performElementDiscovery needs main thread for NSRunningApplication
                // but the AX tree walk and OCR are the slow parts — we handle the
                // app activation on main, then do the heavy work here.
                var pid: pid_t?
                var bundleID = "(unknown)"
                pid = ElementDiscovery.findWindowOwnerPID(area: capturedArea)
                if let p = pid {
                    NSLog("[agent-vision] Found window owner PID=\(p)")
                    DispatchQueue.main.sync {
                        let app = NSRunningApplication(processIdentifier: p)
                        bundleID = app?.bundleIdentifier ?? "(unknown)"
                        NSLog("[agent-vision] Target app: \(bundleID)")
                        app?.activate()
                    }
                    Thread.sleep(forTimeInterval: 0.3)

                    let appElement = AXUIElementCreateApplication(p)
                    AXUIElementSetAttributeValue(
                        appElement,
                        "AXEnhancedUserInterface" as CFString,
                        kCFBooleanTrue
                    )
                    var needsBrowserWait = false
                    DispatchQueue.main.sync {
                        if let s = weakSelf, !s.enhancedUIPIDs.contains(p) {
                            s.enhancedUIPIDs.insert(p)
                            let isBrowser = ["com.google.Chrome", "com.apple.Safari",
                                             "company.thebrowser.Browser", "org.mozilla.firefox",
                                             "com.microsoft.edgemac"].contains(where: { bundleID.contains($0) })
                            needsBrowserWait = isBrowser
                        }
                    }
                    if needsBrowserWait {
                        NSLog("[agent-vision] Browser detected (\(bundleID)) — waiting 2s for AX tree")
                        Thread.sleep(forTimeInterval: 2.0)
                    }
                } else {
                    NSLog("[agent-vision] WARNING: No window owner PID found for area")
                }

                NSLog("[agent-vision] AX discovery pass 1 (depth=15)")
                ElementDiscovery.maxDepth = 15
                var axElements = ElementDiscovery.discover(area: capturedArea)
                let actionableCount = axElements.filter { [.button, .link, .textField, .checkbox].contains($0.role) }.count
                NSLog("[agent-vision] AX pass 1: \(axElements.count) elements (\(actionableCount) actionable)")
                if actionableCount < 3 {
                    NSLog("[agent-vision] Too few actionable — AX discovery pass 2 (depth=25)")
                    ElementDiscovery.maxDepth = 25
                    axElements = ElementDiscovery.discover(area: capturedArea)
                    NSLog("[agent-vision] AX pass 2: \(axElements.count) elements")
                }

                let rect = CGRect(x: capturedArea.x, y: capturedArea.y, width: capturedArea.width, height: capturedArea.height)
                var ocrElements: [DiscoveredElement] = []
                NSLog("[agent-vision] Starting OCR text discovery")
                do {
                    let image = try captureScreenRect(rect)
                    ocrElements = TextDiscovery.discover(
                        image: image,
                        areaWidth: capturedArea.width,
                        areaHeight: capturedArea.height,
                        existingElements: axElements,
                        startIndex: axElements.count + 1
                    )
                    NSLog("[agent-vision] OCR found \(ocrElements.count) text elements")
                } catch {
                    NSLog("[agent-vision] WARNING: Screen capture failed — \(error)")
                }

                let allElements = axElements + ocrElements
                scanResult = ElementScanResult(area: capturedArea, elements: allElements)

                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                NSLog("[agent-vision] discoverElements complete: \(scanResult.elementCount) elements in \(String(format: "%.2f", elapsed))s")

                let elementsPath = Config.elementsFilePath(for: sid)
                try? ElementStore.write(scanResult, to: elementsPath, createDirectory: sessionDir)
                let result = ActionResult(success: true, message: "Discovered \(scanResult.elementCount) elements")
                try? ActionFile.writeResult(result, to: resultPath, createDirectory: sessionDir)

                DispatchQueue.main.async { [weak weakSelf] in
                    weakSelf?.isProcessingAction = false
                }
            }
            return
        }

        // ALL CGEvent actions require the target window to have keyboard focus.
        // Auto-wait for focus with exponential backoff instead of failing immediately.
        let capturedArea = area
        let capturedAction = action
        let capturedFocusTimeout = focusTimeout
        nonisolated(unsafe) let weakSelf2 = self
        DispatchQueue.global(qos: .userInitiated).async { [weak weakSelf2] in
            let owner = capturedArea.windowOwner ?? "the session window"

            // Wait for focus with exponential backoff (0.5s → 1s → 2s → 4s → 8s, capped)
            var delay: TimeInterval = 0.5
            let maxDelay: TimeInterval = 8
            var hasPrintedWaiting = false
            let focusDeadline = Date().addingTimeInterval(capturedFocusTimeout)
            var timedOut = false

            while true {
                var focused = false
                DispatchQueue.main.sync {
                    focused = weakSelf2?.isSessionWindowFrontmost(area: capturedArea) ?? false
                }
                if focused { break }

                if Date() >= focusDeadline {
                    timedOut = true
                    break
                }

                if !hasPrintedWaiting {
                    NSLog("[agent-vision] Waiting for \(owner) to have focus before executing action (timeout: \(Int(capturedFocusTimeout))s)...")
                    hasPrintedWaiting = true
                }

                Thread.sleep(forTimeInterval: delay)
                delay = min(delay * 2, maxDelay)
            }

            if timedOut {
                NSLog("[agent-vision] TIMEOUT: \(owner) did not gain focus within \(Int(capturedFocusTimeout))s")
                let result = ActionResult(success: false, message: "Error: \(owner) did not gain focus within \(Int(capturedFocusTimeout))s. Switch focus to it and retry.")
                try? ActionFile.writeResult(result, to: resultPath, createDirectory: sessionDir)
                DispatchQueue.main.async { [weak weakSelf2] in
                    weakSelf2?.isProcessingAction = false
                }
                return
            }

            if hasPrintedWaiting {
                NSLog("[agent-vision] \(owner) has focus — executing queued action")
            }

            // Window is frontmost — execute the CGEvent action
            do {
                let absoluteAction = capturedAction.toAbsolute(area: capturedArea)
                let message = try weakSelf2?.executeAction(absoluteAction, original: capturedAction) ?? "Action executed"
                NSLog("[agent-vision] Action executed: \(message)")

                DispatchQueue.main.async { [weak weakSelf2] in
                    weakSelf2?.onFeedback?(capturedAction, capturedArea)
                }

                let result = ActionResult(success: true, message: message)
                try ActionFile.writeResult(result, to: resultPath, createDirectory: sessionDir)
            } catch {
                NSLog("[agent-vision] Action FAILED with error: \(error)")
                let result = ActionResult(success: false, message: "Error: \(error)")
                try? ActionFile.writeResult(result, to: resultPath, createDirectory: sessionDir)
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            if elapsed > 0.5 {
                NSLog("[agent-vision] WARNING: Action took \(String(format: "%.2f", elapsed))s (>0.5s)")
            }
            DispatchQueue.main.async { [weak weakSelf2] in
                weakSelf2?.isProcessingAction = false
            }
        }
    }

    /// Returns true only if the session's target window is the frontmost window
    /// at its position AND its owning app has keyboard focus.
    /// When `requireKeyboardFocus` is true (for type/key actions), also verifies
    /// the specific window has keyboard focus using the Accessibility API —
    /// not just that the app is active (handles multiple windows from same app).
    private func isSessionWindowFrontmost(area: CaptureArea) -> Bool {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else {
            NSLog("[agent-vision] Focus check: CGWindowListCopyWindowInfo failed")
            return false
        }

        let myPID = ProcessInfo.processInfo.processIdentifier
        let areaCenter = CGPoint(x: area.x + area.width / 2, y: area.y + area.height / 2)
        let targetWindowNumber = area.windowNumber

        // Walk front-to-back. First non-agent-vision window at the area center
        // is what would actually receive the CGEvent.
        for info in list {
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let wx = boundsDict["X"] as? CGFloat,
                  let wy = boundsDict["Y"] as? CGFloat,
                  let ww = boundsDict["Width"] as? CGFloat,
                  let wh = boundsDict["Height"] as? CGFloat else { continue }

            // Skip our own windows (toolbar, pill overlay)
            if pid == myPID { continue }
            // Skip non-standard window layers (menubar, dock, etc)
            if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 { continue }

            let frame = CGRect(x: wx, y: wy, width: ww, height: wh)
            if frame.contains(areaCenter) {
                let frontmostNum = info[kCGWindowNumber as String] as? UInt32
                let frontmostOwner = info[kCGWindowOwnerName as String] as? String ?? "unknown"

                // If we have a target window number, the frontmost window must be that exact window
                if let targetNum = targetWindowNumber, frontmostNum != targetNum {
                    NSLog("[agent-vision] Focus check FAILED: frontmost is \(frontmostOwner) (#\(frontmostNum ?? 0)), expected #\(targetNum)")
                    return false
                }

                // Verify the owning app is active
                guard let app = NSRunningApplication(processIdentifier: pid), app.isActive else {
                    NSLog("[agent-vision] Focus check FAILED: \(frontmostOwner) is on top but app is not active")
                    return false
                }

                // Also verify the specific WINDOW has keyboard focus — not just the app.
                // Handles multiple windows from the same app (e.g. two Ghostty terminals).
                if targetWindowNumber != nil {
                    if !isFocusedWindow(pid: pid, targetBounds: frame) {
                        NSLog("[agent-vision] Focus check FAILED: \(frontmostOwner) is active but a different window has keyboard focus")
                        return false
                    }
                }

                NSLog("[agent-vision] Focus check PASSED: \(frontmostOwner) is frontmost and active")
                return true
            }
        }

        NSLog("[agent-vision] Focus check FAILED: no window found at area center")
        return false
    }

    /// Uses the Accessibility API to check if the app's focused window matches
    /// the target window bounds. Returns true if the focused window's position
    /// and size match (within tolerance) the target.
    private func isFocusedWindow(pid: pid_t, targetBounds: CGRect) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindowRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
        guard result == .success, let focusedWindow = focusedWindowRef else {
            // Can't determine focused window — refuse action to be safe
            NSLog("[agent-vision] isFocusedWindow: cannot get focused window via AX API (error: \(result.rawValue)), refusing action")
            return false
        }

        let windowElement = focusedWindow as! AXUIElement

        // Get focused window position
        var positionRef: CFTypeRef?
        AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &positionRef)
        var position = CGPoint.zero
        if let positionRef {
            AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        }

        // Get focused window size
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef)
        var size = CGSize.zero
        if let sizeRef {
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        }

        let focusedBounds = CGRect(origin: position, size: size)

        // Compare with tolerance (windows can have slight rounding differences)
        let tolerance: CGFloat = 5
        let matches = abs(focusedBounds.origin.x - targetBounds.origin.x) < tolerance
            && abs(focusedBounds.origin.y - targetBounds.origin.y) < tolerance
            && abs(focusedBounds.width - targetBounds.width) < tolerance
            && abs(focusedBounds.height - targetBounds.height) < tolerance

        if !matches {
            NSLog("[agent-vision] isFocusedWindow: focused window at (\(Int(focusedBounds.origin.x)),\(Int(focusedBounds.origin.y)) \(Int(focusedBounds.width))x\(Int(focusedBounds.height))) does not match target (\(Int(targetBounds.origin.x)),\(Int(targetBounds.origin.y)) \(Int(targetBounds.width))x\(Int(targetBounds.height)))")
        }

        return matches
    }

    /// Track PIDs we've already signaled for enhanced accessibility.
    private var enhancedUIPIDs: Set<pid_t> = []

    private nonisolated func executeAction(_ action: ActionRequest, original: ActionRequest) throws -> String {
        let source = CGEventSource(stateID: .hidSystemState)

        switch action {
        case .click(let pt):
            let point = CGPoint(x: pt.x, y: pt.y)
            let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
            let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
            mouseDown?.post(tap: .cghidEventTap)
            mouseUp?.post(tap: .cghidEventTap)
            if case .click(let orig) = original {
                return "Clicked at (\(Int(orig.x)), \(Int(orig.y)))"
            }
            return "Clicked"

        case .type(let text):
            for char in text {
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
                var chars = Array(String(char).utf16)
                keyDown?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
                keyUp?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
                keyDown?.post(tap: .cghidEventTap)
                keyUp?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.01)
            }
            return "Typed \"\(text)\""

        case .key(let keyStr):
            let parsed = try KeyMapping.parse(keyStr)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: parsed.keyCode, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: parsed.keyCode, keyDown: false)
            keyDown?.flags = parsed.modifiers
            keyUp?.flags = parsed.modifiers
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            return "Pressed \(keyStr)"

        case .scroll(let delta, let pt):
            let point = CGPoint(x: pt.x, y: pt.y)
            let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
            move?.post(tap: .cghidEventTap)
            let scrollEvent = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: Int32(delta.dy), wheel2: Int32(delta.dx), wheel3: 0)
            scrollEvent?.post(tap: .cghidEventTap)
            if case .scroll(_, let origPt) = original {
                return "Scrolled by (\(Int(delta.dx)), \(Int(delta.dy))) at (\(Int(origPt.x)), \(Int(origPt.y)))"
            }
            return "Scrolled"

        case .drag(let from, let to):
            let startPoint = CGPoint(x: from.x, y: from.y)
            let endPoint = CGPoint(x: to.x, y: to.y)

            let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: startPoint, mouseButton: .left)
            mouseDown?.post(tap: .cghidEventTap)

            let dx = endPoint.x - startPoint.x
            let dy = endPoint.y - startPoint.y
            let distance = sqrt(dx * dx + dy * dy)
            let steps = max(Int(distance / 10), 1)

            for i in 1...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let current = CGPoint(x: startPoint.x + dx * t, y: startPoint.y + dy * t)
                let dragEvent = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged, mouseCursorPosition: current, mouseButton: .left)
                dragEvent?.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.01)
            }

            let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: endPoint, mouseButton: .left)
            mouseUp?.post(tap: .cghidEventTap)

            if case .drag(let origFrom, let origTo) = original {
                return "Dragged from (\(Int(origFrom.x)), \(Int(origFrom.y))) to (\(Int(origTo.x)), \(Int(origTo.y)))"
            }
            return "Dragged"

        case .discoverElements, .clickElement, .typeElement:
            // Handled before executeAction is called; should never reach here
            return "Action handled separately"
        }
    }
}
