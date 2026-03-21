import CoreGraphics

public struct ParsedKey: Sendable {
    public let keyCode: CGKeyCode
    public let modifiers: CGEventFlags
}

public enum KeyMappingError: Error, CustomStringConvertible {
    case unknownKey(String)
    public var description: String {
        switch self {
        case .unknownKey(let key):
            return "Error: unknown key '\(key)'. Supported keys: enter, tab, escape, space, delete, backspace, up, down, left, right, home, end, and single characters (a-z, 0-9)."
        }
    }
}

public enum KeyMapping {
    private static let namedKeys: [String: CGKeyCode] = [
        "enter": 0x24, "return": 0x24,
        "tab": 0x30,
        "escape": 0x35, "esc": 0x35,
        "space": 0x31,
        "delete": 0x75,
        "backspace": 0x33,
        "up": 0x7E, "down": 0x7D, "left": 0x7B, "right": 0x7C,
        "home": 0x73, "end": 0x77,
    ]

    private static let charKeys: [Character: CGKeyCode] = [
        "a": 0x00, "b": 0x0B, "c": 0x08, "d": 0x02, "e": 0x0E,
        "f": 0x03, "g": 0x05, "h": 0x04, "i": 0x22, "j": 0x26,
        "k": 0x28, "l": 0x25, "m": 0x2E, "n": 0x2D, "o": 0x1F,
        "p": 0x23, "q": 0x0C, "r": 0x0F, "s": 0x01, "t": 0x11,
        "u": 0x20, "v": 0x09, "w": 0x0D, "x": 0x07, "y": 0x10,
        "z": 0x06,
        "0": 0x1D, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
        "5": 0x17, "6": 0x16, "7": 0x1A, "8": 0x1C, "9": 0x19,
    ]

    private static let modifierMap: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand,
        "shift": .maskShift,
        "alt": .maskAlternate, "option": .maskAlternate,
        "ctrl": .maskControl, "control": .maskControl,
    ]

    public static func parse(_ input: String) throws -> ParsedKey {
        let parts = input.lowercased().split(separator: "+").map(String.init)
        var modifiers: CGEventFlags = []
        var keyPart: String?

        for part in parts {
            if let mod = modifierMap[part] {
                modifiers.insert(mod)
            } else {
                keyPart = part
            }
        }

        guard let key = keyPart else { throw KeyMappingError.unknownKey(input) }

        if let code = namedKeys[key] {
            return ParsedKey(keyCode: code, modifiers: modifiers)
        }
        if key.count == 1, let char = key.first, let code = charKeys[char] {
            return ParsedKey(keyCode: code, modifiers: modifiers)
        }

        throw KeyMappingError.unknownKey(input)
    }
}
