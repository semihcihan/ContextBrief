import Foundation

public struct ShortcutBinding: Codable, Equatable {
    public var keyCode: UInt32
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool

    public init(
        keyCode: UInt32,
        command: Bool,
        option: Bool,
        control: Bool,
        shift: Bool
    ) {
        self.keyCode = keyCode
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }
}

public struct ShortcutPreferences: Codable, Equatable {
    public var addSnapshot: ShortcutBinding
    public var copyCurrentContext: ShortcutBinding

    public init(addSnapshot: ShortcutBinding, copyCurrentContext: ShortcutBinding) {
        self.addSnapshot = addSnapshot
        self.copyCurrentContext = copyCurrentContext
    }
}
