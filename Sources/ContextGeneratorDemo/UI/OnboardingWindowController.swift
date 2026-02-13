import AppKit
import ContextGenerator

final class OnboardingWindowController: NSWindowController {
    private let permissionService: PermissionServicing
    private let appStateService: AppStateService
    private let onComplete: () -> Void

    private let providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let modelField = NSTextField(string: "gpt-4.1-mini")
    private let keyField = NSSecureTextField(frame: .zero)
    private let infoLabel = NSTextField(labelWithString: "")

    init(
        permissionService: PermissionServicing,
        appStateService: AppStateService,
        onComplete: @escaping () -> Void
    ) {
        self.permissionService = permissionService
        self.appStateService = appStateService
        self.onComplete = onComplete

        let contentRect = NSRect(x: 0, y: 0, width: 460, height: 260)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Context Generator Setup"
        super.init(window: window)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Grant permissions and configure model access.")
        title.font = .systemFont(ofSize: 14, weight: .medium)
        stack.addArrangedSubview(title)

        providerPopup.addItems(withTitles: ProviderName.allCases.map(\.rawValue))
        stack.addArrangedSubview(labeledRow(label: "Provider", view: providerPopup))
        stack.addArrangedSubview(labeledRow(label: "Model", view: modelField))
        stack.addArrangedSubview(labeledRow(label: "API Key", view: keyField))

        let requestPermissionsButton = NSButton(title: "Request Permissions", target: self, action: #selector(requestPermissions))
        stack.addArrangedSubview(requestPermissionsButton)

        let completeButton = NSButton(title: "Finish Setup", target: self, action: #selector(finishSetup))
        stack.addArrangedSubview(completeButton)

        infoLabel.stringValue = "Accessibility + Screen Recording are required."
        stack.addArrangedSubview(infoLabel)

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    private func labeledRow(label: String, view: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        let text = NSTextField(labelWithString: "\(label):")
        text.frame.size.width = 110
        text.alignment = .right
        view.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(text)
        row.addArrangedSubview(view)
        return row
    }

    @objc private func requestPermissions() {
        permissionService.requestOnboardingPermissions()
        let hasAll = permissionService.hasAccessibilityPermission() && permissionService.hasScreenRecordingPermission()
        infoLabel.stringValue = hasAll
            ? "Permissions granted."
            : "Grant both permissions in System Settings, then finish setup."
    }

    @objc private func finishSetup() {
        guard
            permissionService.hasAccessibilityPermission(),
            permissionService.hasScreenRecordingPermission()
        else {
            infoLabel.stringValue = "Missing permissions."
            return
        }

        guard let provider = ProviderName(rawValue: providerPopup.titleOfSelectedItem ?? "") else {
            infoLabel.stringValue = "Select a provider."
            return
        }

        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !apiKey.isEmpty else {
            infoLabel.stringValue = "Model and API key are required."
            return
        }

        do {
            try appStateService.configureProvider(provider: provider, model: model, apiKey: apiKey)
            try appStateService.markOnboardingCompleted()
            close()
            onComplete()
        } catch {
            infoLabel.stringValue = "Setup failed: \(error.localizedDescription)"
        }
    }
}
