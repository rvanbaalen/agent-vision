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
        do {
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
                DispatchQueue.global(qos: .userInitiated).async {
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
                    DispatchQueue.main.async { [weak self] in
                        self?.isProcessingAction = false
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
                DispatchQueue.global(qos: .userInitiated).async {
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
                    DispatchQueue.main.async { [weak self] in
                        self?.isProcessingAction = false
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
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
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
                        if let self = self, !self.enhancedUIPIDs.contains(p) {
                            self.enhancedUIPIDs.insert(p)
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

                DispatchQueue.main.async { [weak self] in
                    self?.isProcessingAction = false
                }
            }
            return
        }

        // CGEvent-based actions are fast — keep on main thread
        do {
            let absoluteAction = action.toAbsolute(area: area)
            let message = try executeAction(absoluteAction, original: action)
            NSLog("[agent-vision] Action executed: \(message)")

            onFeedback?(action, area)

            let result = ActionResult(success: true, message: message)
            try ActionFile.writeResult(result, to: resultPath, createDirectory: sessionDir)
        } catch {
            NSLog("[agent-vision] Action FAILED with error: \(error)")
            let result = ActionResult(success: false, message: "Error: \(error)")
            try? ActionFile.writeResult(result, to: resultPath, createDirectory: sessionDir)
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        if elapsed > 0.5 {
            NSLog("[agent-vision] WARNING: Action took \(String(format: "%.2f", elapsed))s (>0.5s) — may cause UI lag")
        }
        isProcessingAction = false
    }

    /// Track PIDs we've already signaled for enhanced accessibility.
    private var enhancedUIPIDs: Set<pid_t> = []

    private func executeAction(_ action: ActionRequest, original: ActionRequest) throws -> String {
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
