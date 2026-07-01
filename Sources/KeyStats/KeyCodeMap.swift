import Foundation

/// macOS virtual keycodes for a standard US ANSI keyboard.
/// Reference: Carbon HIToolbox/Events.h (kVK_* constants).
enum KeyCodeMap {
    static let names: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
        38: "J", 40: "K", 45: "N", 46: "M",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9",
        26: "7", 28: "8", 29: "0",
        24: "=", 27: "-", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\",
        43: ",", 44: "/", 47: ".", 50: "`",
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Escape",
        76: "Enter (Numpad)", 71: "Clear",
        123: "Left Arrow", 124: "Right Arrow", 125: "Down Arrow", 126: "Up Arrow",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
        80: "F19", 90: "F20",
        114: "Help", 115: "Home", 116: "Page Up", 117: "Forward Delete",
        119: "End", 121: "Page Down",
        65: "Decimal (Numpad)", 67: "Multiply (Numpad)", 69: "Add (Numpad)",
        75: "Divide (Numpad)", 78: "Subtract (Numpad)", 81: "Equals (Numpad)",
        82: "0 (Numpad)", 83: "1 (Numpad)", 84: "2 (Numpad)", 85: "3 (Numpad)",
        86: "4 (Numpad)", 87: "5 (Numpad)", 88: "6 (Numpad)", 89: "7 (Numpad)",
        91: "8 (Numpad)", 92: "9 (Numpad)",
        63: "Fn"
    ]

    static func name(for code: Int) -> String {
        names[code] ?? "Key#\(code)"
    }
}
