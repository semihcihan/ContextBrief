import AppKit
import ContextGenerator

final class ShortcutRecorderControl: NSControl {
    var shortcut: ShortcutBinding = ShortcutPreferences.defaultValue.addSnapshot {
        didSet {
            refreshDisplay()
        }
    }

    var onShortcutRecorded: ((ShortcutBinding) -> Void)?
    var onRecordingError: ((String) -> Void)?
    var onRecordingStateChanged: ((Bool) -> Void)?
    var recording: Bool {
        isRecording
    }

    private let valueLabel = NSTextField(labelWithString: "")
    private var isRecording = false {
        didSet {
            if oldValue != isRecording {
                onRecordingStateChanged?(isRecording)
            }
            refreshDisplay()
            refreshAppearance()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        refreshAppearance()
        return became
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        refreshAppearance()
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            return
        }
        if event.keyCode == 53 {
            isRecording = false
            return
        }
        let keyCode = UInt32(event.keyCode)
        guard ShortcutKeyOptions.option(for: keyCode) != nil else {
            onRecordingError?("Use letters (A-Z) or numbers (0-9).")
            NSSound.beep()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let binding = ShortcutBinding(
            keyCode: keyCode,
            command: flags.contains(.command),
            option: flags.contains(.option),
            control: flags.contains(.control),
            shift: flags.contains(.shift)
        )
        if binding.isReservedClipboardShortcut {
            onRecordingError?("Command+C and Command+V are reserved. Choose another shortcut.")
            NSSound.beep()
            return
        }
        guard binding.hasModifier else {
            onRecordingError?("Include at least one modifier key.")
            NSSound.beep()
            return
        }
        shortcut = binding
        isRecording = false
        onShortcutRecorded?(binding)
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.font = .monospacedSystemFont(ofSize: 17, weight: .bold)
        addSubview(valueLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            widthAnchor.constraint(equalToConstant: 180),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        refreshDisplay()
        refreshAppearance()
    }

    private func refreshDisplay() {
        let text = isRecording ? "Type shortcut..." : shortcut.displayText
        valueLabel.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 17, weight: .bold),
                .kern: 4.0
            ]
        )
    }

    private func refreshAppearance() {
        let focused = window?.firstResponder === self
        if isRecording || focused {
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 2
            return
        }
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
    }
}
