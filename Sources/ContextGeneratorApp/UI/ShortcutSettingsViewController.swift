import AppKit
import ContextGenerator

final class ShortcutSettingsViewController: NSViewController {
    private let appStateService: AppStateService
    private let onShortcutsUpdated: () -> [String]
    private let onRecordingStateChanged: (Bool) -> Void

    private let addSnapshotRecorder = ShortcutRecorderControl()
    private let copyCurrentRecorder = ShortcutRecorderControl()

    private let infoLabel = NSTextField(labelWithString: "")
    private let resetDefaultsButton = NSButton(title: "Reset to Defaults", target: nil, action: nil)

    init(
        appStateService: AppStateService,
        onShortcutsUpdated: @escaping () -> [String],
        onRecordingStateChanged: @escaping (Bool) -> Void
    ) {
        self.appStateService = appStateService
        self.onShortcutsUpdated = onShortcutsUpdated
        self.onRecordingStateChanged = onRecordingStateChanged
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadSavedShortcuts()
    }

    private func setupUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.alignment = .left

        let title = NSTextField(labelWithString: "Global Shortcuts")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        stack.addArrangedSubview(title)
        let subtitle = NSTextField(labelWithString: "Click a field and press your combination. Press Esc to cancel recording.")
        subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitle)

        stack.addArrangedSubview(makeActionGroup(
            title: "Add Snapshot to Context",
            detail: "Captures and appends a new snapshot to the active context.",
            recorder: addSnapshotRecorder
        ))
        stack.addArrangedSubview(makeDivider())
        stack.addArrangedSubview(makeActionGroup(
            title: "Copy Current Context",
            detail: "Copies the dense export of your current context to clipboard and pastes it.",
            recorder: copyCurrentRecorder
        ))

        addSnapshotRecorder.onShortcutRecorded = { [weak self] _ in
            self?.saveRecordedShortcuts()
        }
        copyCurrentRecorder.onShortcutRecorded = { [weak self] _ in
            self?.saveRecordedShortcuts()
        }
        addSnapshotRecorder.onRecordingError = { [weak self] text in
            self?.setStatus(text, kind: .error)
        }
        copyCurrentRecorder.onRecordingError = { [weak self] text in
            self?.setStatus(text, kind: .error)
        }
        addSnapshotRecorder.onRecordingStateChanged = { [weak self] _ in
            self?.notifyRecordingStateChanged()
        }
        copyCurrentRecorder.onRecordingStateChanged = { [weak self] _ in
            self?.notifyRecordingStateChanged()
        }

        resetDefaultsButton.target = self
        resetDefaultsButton.action = #selector(resetToDefaults)
        stack.addArrangedSubview(resetDefaultsButton)

        setStatus("Changes are applied immediately.", kind: .info)
        stack.addArrangedSubview(infoLabel)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor)
        ])
    }

    private func makeActionGroup(
        title: String,
        detail: String,
        recorder: ShortcutRecorderControl
    ) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 2

        let row = NSStackView(views: [NSTextField(labelWithString: "Shortcut"), recorder])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY

        let group = NSStackView(views: [titleLabel, detailLabel, row])
        group.orientation = .vertical
        group.spacing = 8
        group.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        return group
    }

    private func makeDivider() -> NSBox {
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return divider
    }

    private func loadSavedShortcuts() {
        let shortcuts = (try? appStateService.shortcuts()) ?? .defaultValue
        addSnapshotRecorder.shortcut = shortcuts.addSnapshot
        copyCurrentRecorder.shortcut = shortcuts.copyCurrentContext
    }

    private func saveRecordedShortcuts() {
        let addSnapshot = addSnapshotRecorder.shortcut
        let copyCurrentContext = copyCurrentRecorder.shortcut
        if addSnapshot.isReservedClipboardShortcut || copyCurrentContext.isReservedClipboardShortcut {
            setStatus("Command+C and Command+V are reserved. Choose another shortcut.", kind: .error)
            return
        }
        guard addSnapshot != copyCurrentContext else {
            setStatus("Shortcuts must be different.", kind: .error)
            return
        }
        let updated = ShortcutPreferences(addSnapshot: addSnapshot, copyCurrentContext: copyCurrentContext)
        do {
            try appStateService.updateShortcuts(updated)
            let failed = onShortcutsUpdated()
            if failed.isEmpty {
                setStatus("Changes are applied immediately.", kind: .info)
                return
            }
            setStatus("Unavailable globally: \(failed.joined(separator: ", "))", kind: .error)
        } catch {
            setStatus("Failed to save shortcuts.", kind: .error)
        }
    }

    @objc private func resetToDefaults() {
        let defaults = ShortcutPreferences.defaultValue
        addSnapshotRecorder.shortcut = defaults.addSnapshot
        copyCurrentRecorder.shortcut = defaults.copyCurrentContext
        saveRecordedShortcuts()
    }

    private enum StatusKind {
        case info
        case error
    }

    private func setStatus(_ text: String, kind: StatusKind) {
        infoLabel.stringValue = text
        infoLabel.textColor = kind == .error ? .systemRed : .secondaryLabelColor
    }

    private func notifyRecordingStateChanged() {
        onRecordingStateChanged(addSnapshotRecorder.recording || copyCurrentRecorder.recording)
    }
}
