import ContextGenerator
import Foundation

struct ShortcutKeyOption {
    let keyCode: UInt32
    let label: String
    let keyEquivalent: String
}

enum ShortcutKeyOptions {
    static let all: [ShortcutKeyOption] = [
        ShortcutKeyOption(keyCode: 0, label: "A", keyEquivalent: "a"),
        ShortcutKeyOption(keyCode: 11, label: "B", keyEquivalent: "b"),
        ShortcutKeyOption(keyCode: 8, label: "C", keyEquivalent: "c"),
        ShortcutKeyOption(keyCode: 2, label: "D", keyEquivalent: "d"),
        ShortcutKeyOption(keyCode: 14, label: "E", keyEquivalent: "e"),
        ShortcutKeyOption(keyCode: 3, label: "F", keyEquivalent: "f"),
        ShortcutKeyOption(keyCode: 5, label: "G", keyEquivalent: "g"),
        ShortcutKeyOption(keyCode: 4, label: "H", keyEquivalent: "h"),
        ShortcutKeyOption(keyCode: 34, label: "I", keyEquivalent: "i"),
        ShortcutKeyOption(keyCode: 38, label: "J", keyEquivalent: "j"),
        ShortcutKeyOption(keyCode: 40, label: "K", keyEquivalent: "k"),
        ShortcutKeyOption(keyCode: 37, label: "L", keyEquivalent: "l"),
        ShortcutKeyOption(keyCode: 46, label: "M", keyEquivalent: "m"),
        ShortcutKeyOption(keyCode: 45, label: "N", keyEquivalent: "n"),
        ShortcutKeyOption(keyCode: 31, label: "O", keyEquivalent: "o"),
        ShortcutKeyOption(keyCode: 35, label: "P", keyEquivalent: "p"),
        ShortcutKeyOption(keyCode: 12, label: "Q", keyEquivalent: "q"),
        ShortcutKeyOption(keyCode: 15, label: "R", keyEquivalent: "r"),
        ShortcutKeyOption(keyCode: 1, label: "S", keyEquivalent: "s"),
        ShortcutKeyOption(keyCode: 17, label: "T", keyEquivalent: "t"),
        ShortcutKeyOption(keyCode: 32, label: "U", keyEquivalent: "u"),
        ShortcutKeyOption(keyCode: 9, label: "V", keyEquivalent: "v"),
        ShortcutKeyOption(keyCode: 13, label: "W", keyEquivalent: "w"),
        ShortcutKeyOption(keyCode: 7, label: "X", keyEquivalent: "x"),
        ShortcutKeyOption(keyCode: 16, label: "Y", keyEquivalent: "y"),
        ShortcutKeyOption(keyCode: 6, label: "Z", keyEquivalent: "z"),
        ShortcutKeyOption(keyCode: 18, label: "1", keyEquivalent: "1"),
        ShortcutKeyOption(keyCode: 19, label: "2", keyEquivalent: "2"),
        ShortcutKeyOption(keyCode: 20, label: "3", keyEquivalent: "3"),
        ShortcutKeyOption(keyCode: 21, label: "4", keyEquivalent: "4"),
        ShortcutKeyOption(keyCode: 23, label: "5", keyEquivalent: "5"),
        ShortcutKeyOption(keyCode: 22, label: "6", keyEquivalent: "6"),
        ShortcutKeyOption(keyCode: 26, label: "7", keyEquivalent: "7"),
        ShortcutKeyOption(keyCode: 28, label: "8", keyEquivalent: "8"),
        ShortcutKeyOption(keyCode: 25, label: "9", keyEquivalent: "9"),
        ShortcutKeyOption(keyCode: 29, label: "0", keyEquivalent: "0")
    ]

    static func label(for keyCode: UInt32) -> String {
        all.first(where: { $0.keyCode == keyCode })?.label ?? "Key \(keyCode)"
    }

    static func option(for keyCode: UInt32) -> ShortcutKeyOption? {
        all.first(where: { $0.keyCode == keyCode })
    }

    static func keyEquivalent(for keyCode: UInt32) -> String {
        option(for: keyCode)?.keyEquivalent ?? ""
    }
}

extension ShortcutBinding {
    var hasModifier: Bool {
        command || option || control || shift
    }

    var isReservedClipboardShortcut: Bool {
        command
            && !option
            && !control
            && !shift
            && (keyCode == 8 || keyCode == 9)
    }

    var displayText: String {
        let symbols = [
            control ? "⌃" : "",
            option ? "⌥" : "",
            shift ? "⇧" : "",
            command ? "⌘" : ""
        ].joined()
        return "\(symbols)\(ShortcutKeyOptions.label(for: keyCode))"
    }
}
