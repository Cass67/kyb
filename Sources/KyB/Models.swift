import Carbon.HIToolbox
import Foundation

struct Mapping: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var combo: KeyCombo
    var text: String
    var enabled: Bool
    var injectionMode: InjectionMode
    var typingDelayMs: Int

    init(
        id: UUID = UUID(),
        name: String = "",
        combo: KeyCombo = .init(keyCode: UInt32(kVK_F6), modifiers: [.control, .option]),
        text: String = "",
        enabled: Bool = true,
        injectionMode: InjectionMode = .bestEffort,
        typingDelayMs: Int = 2
    ) {
        self.id = id
        self.name = name
        self.combo = combo
        self.text = text
        self.enabled = enabled
        self.injectionMode = injectionMode
        self.typingDelayMs = typingDelayMs
    }

    enum CodingKeys: String, CodingKey {
        case id, name, combo, text, enabled, injectionMode, typingDelayMs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        combo = try c.decodeIfPresent(KeyCombo.self, forKey: .combo) ?? .init(keyCode: UInt32(kVK_F6), modifiers: [.control, .option])
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        injectionMode = try c.decodeIfPresent(InjectionMode.self, forKey: .injectionMode) ?? .bestEffort
        typingDelayMs = try c.decodeIfPresent(Int.self, forKey: .typingDelayMs) ?? 2
    }
}

enum InjectionMode: String, Codable, CaseIterable, Identifiable {
    case bestEffort
    case aggressiveBestEffort
    case accessibilityThenPaste
    case accessibilityOnly
    case pasteAndRestoreClipboard
    case pasteAndClearClipboard
    case typeCharacters

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .bestEffort: "Auto best effort"
        case .aggressiveBestEffort: "Aggressive auto (may duplicate)"
        case .accessibilityThenPaste: "AX insert, fallback paste"
        case .accessibilityOnly: "AX insert only"
        case .pasteAndRestoreClipboard: "Paste + restore clipboard"
        case .pasteAndClearClipboard: "Paste + clear clipboard"
        case .typeCharacters: "Type characters"
        }
    }
}

struct KeyCombo: Codable, Hashable, CustomStringConvertible {
    var keyCode: UInt32
    var modifiers: ModifierFlags

    var description: String {
        let parts = modifiers.displayParts + [KeyNames.name(for: keyCode)]
        return parts.joined(separator: "")
    }
}

struct ModifierFlags: OptionSet, Codable, Hashable {
    let rawValue: UInt32

    static let command = ModifierFlags(rawValue: 1 << 0)
    static let option = ModifierFlags(rawValue: 1 << 1)
    static let control = ModifierFlags(rawValue: 1 << 2)
    static let shift = ModifierFlags(rawValue: 1 << 3)
    static let function = ModifierFlags(rawValue: 1 << 4)

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    init(eventModifiers: UInt) {
        var flags: ModifierFlags = []
        if eventModifiers & UInt(cmdKey) != 0 { flags.insert(.command) }
        if eventModifiers & UInt(optionKey) != 0 { flags.insert(.option) }
        if eventModifiers & UInt(controlKey) != 0 { flags.insert(.control) }
        if eventModifiers & UInt(shiftKey) != 0 { flags.insert(.shift) }
        flags.insert(.function)
        self = flags
    }

    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }

    var displayParts: [String] {
        var parts: [String] = []
        if contains(.control) { parts.append("⌃") }
        if contains(.option) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        return parts
    }
}

enum KeyNames {
    static func name(for code: UInt32) -> String {
        switch Int(code) {
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_ANSI_A ... kVK_ANSI_Z:
            let names = [kVK_ANSI_A: "A", kVK_ANSI_S: "S", kVK_ANSI_D: "D", kVK_ANSI_F: "F", kVK_ANSI_H: "H", kVK_ANSI_G: "G", kVK_ANSI_Z: "Z", kVK_ANSI_X: "X", kVK_ANSI_C: "C", kVK_ANSI_V: "V", kVK_ANSI_B: "B", kVK_ANSI_Q: "Q", kVK_ANSI_W: "W", kVK_ANSI_E: "E", kVK_ANSI_R: "R", kVK_ANSI_Y: "Y", kVK_ANSI_T: "T", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_6: "6", kVK_ANSI_5: "5", kVK_ANSI_Equal: "=", kVK_ANSI_9: "9", kVK_ANSI_7: "7", kVK_ANSI_Minus: "-", kVK_ANSI_8: "8", kVK_ANSI_0: "0", kVK_ANSI_RightBracket: "]", kVK_ANSI_O: "O", kVK_ANSI_U: "U", kVK_ANSI_LeftBracket: "[", kVK_ANSI_I: "I", kVK_ANSI_P: "P", kVK_ANSI_L: "L", kVK_ANSI_J: "J", kVK_ANSI_Quote: "'", kVK_ANSI_K: "K", kVK_ANSI_Semicolon: ";", kVK_ANSI_Backslash: "\\", kVK_ANSI_Comma: ",", kVK_ANSI_Slash: "/", kVK_ANSI_N: "N", kVK_ANSI_M: "M", kVK_ANSI_Period: ".", kVK_ANSI_Grave: "`"]
            return names[Int(code)] ?? "Key \(code)"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        default: return "Key \(code)"
        }
    }
}
