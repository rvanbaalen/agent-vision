import AppKit
import ClaudeVisionShared
import CoreGraphics

@MainActor
class ActionWatcher {
    private var timer: Timer?
    private var onFeedback: ((ActionRequest, CaptureArea) -> Void)?
    private let sessionID: String

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func start(onFeedback: @escaping (ActionRequest, CaptureArea) -> Void) {
        self.onFeedback = onFeedback
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForAction()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkForAction() {
        let actionPath = Config.actionFilePath(for: sessionID)
        let resultPath = Config.actionResultFilePath(for: sessionID)
        let sessionDir = Config.sessionDirectory(for: sessionID)
        guard FileManager.default.fileExists(atPath: actionPath.path) else { return }

        do {
            let action = try ActionFile.readAction(from: actionPath)

            guard let state = try StateFile.read(from: Config.stateFilePath(for: sessionID)),
                  let area = state.area else {
                let result = ActionResult(success: false, message: "No area selected")
                try? ActionFile.writeResult(result, to: resultPath, createDirectory: sessionDir)
                ActionFile.delete(at: actionPath)
                return
            }

            guard AXIsProcessTrusted() else {
                let result = ActionResult(success: false, message: "Error: Accessibility permission required. Enable it in System Settings > Privacy & Security > Accessibility.")
                try? ActionFile.writeResult(result, to: resultPath, createDirectory: sessionDir)
                ActionFile.delete(at: actionPath)
                return
            }

            let absoluteAction = action.toAbsolute(area: area)
            let message = try executeAction(absoluteAction, original: action)

            onFeedback?(action, area)

            let result = ActionResult(success: true, message: message)
            try ActionFile.writeResult(result, to: resultPath, createDirectory: sessionDir)
        } catch {
            let result = ActionResult(success: false, message: "Error: \(error)")
            try? ActionFile.writeResult(result, to: resultPath, createDirectory: sessionDir)
        }

        ActionFile.delete(at: actionPath)
    }

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
        }
    }
}
