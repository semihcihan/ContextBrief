import AppKit
import ContextGenerator

final class SetupViewController: NSViewController {
    private let permissionService: PermissionServicing
    private let appStateService: AppStateService
    private let onComplete: () -> Void

    private let providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let modelField = NSTextField(string: "gpt-4.1-mini")
    private let keyField = NSSecureTextField(frame: .zero)
    private let infoLabel = NSTextField(labelWithString: "")
    private let requestPermissionsButton = NSButton(title: "Request Permissions", target: nil, action: nil)
    private let finishSetupButton = NSButton(title: "Finish Setup", target: nil, action: nil)
    private var setupValidationInProgress = false

    init(
        permissionService: PermissionServicing,
        appStateService: AppStateService,
        onComplete: @escaping () -> Void
    ) {
        self.permissionService = permissionService
        self.appStateService = appStateService
        self.onComplete = onComplete
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
    }

    private func setupUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.alignment = .centerX

        let title = NSTextField(labelWithString: "Grant permissions and configure model access.")
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.alignment = .center
        stack.addArrangedSubview(title)

        providerPopup.removeAllItems()
        for provider in ProviderName.allCases {
            providerPopup.addItem(withTitle: provider.displayName)
            providerPopup.lastItem?.representedObject = provider.rawValue
        }
        providerPopup.selectItem(at: 0)

        let fieldColumn = NSStackView()
        fieldColumn.orientation = .vertical
        fieldColumn.spacing = 8
        fieldColumn.translatesAutoresizingMaskIntoConstraints = false
        fieldColumn.addArrangedSubview(labeledRow(label: "Provider", view: providerPopup))
        fieldColumn.addArrangedSubview(labeledRow(label: "Model", view: modelField))
        fieldColumn.addArrangedSubview(labeledRow(label: "API Key", view: keyField))
        stack.addArrangedSubview(fieldColumn)
        stack.setCustomSpacing(12, after: fieldColumn)

        requestPermissionsButton.target = self
        requestPermissionsButton.action = #selector(requestPermissions)
        finishSetupButton.target = self
        finishSetupButton.action = #selector(finishSetup)
        let buttonColumn = NSStackView(views: [requestPermissionsButton, finishSetupButton])
        buttonColumn.orientation = .vertical
        buttonColumn.spacing = 6
        buttonColumn.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(buttonColumn)
        stack.setCustomSpacing(12, after: buttonColumn)

        infoLabel.stringValue = "Accessibility + Screen Recording are required."
        infoLabel.alignment = .center
        stack.addArrangedSubview(infoLabel)

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            fieldColumn.widthAnchor.constraint(equalToConstant: 460),
            buttonColumn.widthAnchor.constraint(equalToConstant: 240),
            requestPermissionsButton.widthAnchor.constraint(equalTo: finishSetupButton.widthAnchor),
            requestPermissionsButton.heightAnchor.constraint(equalToConstant: 30),
            finishSetupButton.heightAnchor.constraint(equalTo: requestPermissionsButton.heightAnchor)
        ])
    }

    private func labeledRow(label: String, view: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        row.distribution = .fill
        row.translatesAutoresizingMaskIntoConstraints = false
        let text = NSTextField(labelWithString: "\(label):")
        text.alignment = .right
        text.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(text)
        row.addArrangedSubview(view)
        NSLayoutConstraint.activate([
            text.widthAnchor.constraint(equalToConstant: 95),
            view.heightAnchor.constraint(equalToConstant: 26)
        ])
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
        guard !setupValidationInProgress else {
            return
        }
        guard
            permissionService.hasAccessibilityPermission(),
            permissionService.hasScreenRecordingPermission()
        else {
            infoLabel.stringValue = "Missing permissions."
            return
        }

        guard
            let selectedProviderRawValue = providerPopup.selectedItem?.representedObject as? String,
            let provider = ProviderName(rawValue: selectedProviderRawValue)
        else {
            infoLabel.stringValue = "Select a provider."
            return
        }

        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !apiKey.isEmpty else {
            infoLabel.stringValue = "Model and API key are required."
            return
        }

        setSetupControlsEnabled(false)
        infoLabel.stringValue = "Validating model access..."
        setupValidationInProgress = true

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                try await self.validateProvider(provider: provider, model: model, apiKey: apiKey)
                try self.appStateService.configureProvider(provider: provider, model: model, apiKey: apiKey)
                try self.appStateService.markOnboardingCompleted()
                await MainActor.run {
                    self.setupValidationInProgress = false
                    self.setSetupControlsEnabled(true)
                    self.onComplete()
                }
            } catch {
                await MainActor.run {
                    self.setupValidationInProgress = false
                    self.setSetupControlsEnabled(true)
                    self.infoLabel.stringValue = "Setup failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func setSetupControlsEnabled(_ enabled: Bool) {
        providerPopup.isEnabled = enabled
        modelField.isEnabled = enabled
        keyField.isEnabled = enabled
        requestPermissionsButton.isEnabled = enabled
        finishSetupButton.isEnabled = enabled
    }

    private func validateProvider(provider: ProviderName, model: String, apiKey: String) async throws {
        let client = ProviderClientFactory.make(provider: provider)
        let request = DensificationRequest(
            inputText: "Health check. Reply with OK.",
            appName: "Context Generator",
            windowTitle: "Setup Validation"
        )
        _ = try await client.densify(
            request: request,
            apiKey: apiKey,
            model: model
        )
    }
}

private extension ProviderName {
    var displayName: String {
        switch self {
        case .openai:
            return "OpenAI"
        case .anthropic:
            return "Anthropic"
        case .gemini:
            return "Gemini"
        }
    }
}
