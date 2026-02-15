import AppKit
import ContextGenerator

final class SetupViewController: NSViewController, NSTextFieldDelegate {

    private let permissionService: PermissionServicing
    private let appStateService: AppStateService
    private let onComplete: () -> Void

    private let providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let modelField = NSTextField(string: "gpt-4.1-mini")
    private let keyField = NSSecureTextField(frame: .zero)
    private let infoLabel = NSTextField(labelWithString: "")
    private let validationSpinner = NSProgressIndicator()
    private let statusBalanceSpacer = NSView()
    private let requestPermissionsButton = NSButton(title: "Request Permissions", target: nil, action: nil)
    private let finishSetupButton = NSButton(title: "Finish Setup", target: nil, action: nil)
    private var setupValidationInProgress = false
    private let defaultInfoMessage = "Accessibility + Screen Recording are required."

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
        refreshPermissionsStatus()
        loadSavedProviderSelection()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshPermissionsStatus()
        loadSavedProviderSelection()
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
        providerPopup.target = self
        providerPopup.action = #selector(providerSelectionChanged)
        modelField.delegate = self
        modelField.target = self
        modelField.action = #selector(inputFieldsChanged)
        keyField.delegate = self
        keyField.target = self
        keyField.action = #selector(inputFieldsChanged)
        validationSpinner.style = .spinning
        validationSpinner.controlSize = .small
        validationSpinner.isDisplayedWhenStopped = false
        validationSpinner.translatesAutoresizingMaskIntoConstraints = false
        statusBalanceSpacer.translatesAutoresizingMaskIntoConstraints = false

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

        infoLabel.stringValue = defaultInfoMessage
        infoLabel.alignment = .center
        let statusRow = NSStackView(views: [validationSpinner, infoLabel, statusBalanceSpacer])
        statusRow.orientation = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .centerY
        statusRow.distribution = .fill
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(statusRow)

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
            finishSetupButton.heightAnchor.constraint(equalTo: requestPermissionsButton.heightAnchor),
            validationSpinner.widthAnchor.constraint(equalToConstant: 14),
            validationSpinner.heightAnchor.constraint(equalToConstant: 14),
            statusBalanceSpacer.widthAnchor.constraint(equalTo: validationSpinner.widthAnchor),
            statusBalanceSpacer.heightAnchor.constraint(equalTo: validationSpinner.heightAnchor)
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
        refreshPermissionsStatus()
        infoLabel.stringValue = permissionService.hasAccessibilityPermission() && permissionService.hasScreenRecordingPermission()
            ? "Permissions granted."
            : "Grant both permissions in System Settings, then finish setup."
    }

    @objc private func finishSetup() {
        guard !setupValidationInProgress else {
            return
        }
        view.window?.makeFirstResponder(nil)
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
        guard !model.isEmpty else {
            infoLabel.stringValue = "Model is required."
            return
        }

        let apiKeyForValidation = normalizedAPIKey(keyField.stringValue)
        keyField.stringValue = apiKeyForValidation
        infoLabel.stringValue = "Validating model access..."
        guard !apiKeyForValidation.isEmpty else {
            infoLabel.stringValue = "API key is required."
            return
        }

        setValidationInProgress(true)
        updateActionAvailability()

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                try await self.validateProvider(provider: provider, model: model, apiKey: apiKeyForValidation)
                try self.appStateService.configureProvider(
                    provider: provider,
                    model: model,
                    apiKey: apiKeyForValidation
                )
                try self.appStateService.markOnboardingCompleted()
                await MainActor.run {
                    self.setValidationInProgress(false)
                    self.updateActionAvailability()
                    self.infoLabel.stringValue = "Setup complete."
                    self.onComplete()
                }
            } catch {
                await MainActor.run {
                    self.setValidationInProgress(false)
                    self.updateActionAvailability()
                    self.infoLabel.stringValue = "Setup failed."
                    self.presentSetupErrorAlert(error)
                }
            }
        }
    }

    private func setValidationInProgress(_ inProgress: Bool) {
        setupValidationInProgress = inProgress
        providerPopup.isEnabled = !inProgress
        modelField.isEditable = !inProgress
        keyField.isEditable = !inProgress
        if inProgress {
            validationSpinner.startAnimation(nil)
            finishSetupButton.title = "Validating..."
            return
        }
        validationSpinner.stopAnimation(nil)
        finishSetupButton.title = "Finish Setup"
    }

    @objc private func inputFieldsChanged() {
        updateActionAvailability()
    }

    func controlTextDidChange(_ notification: Notification) {
        normalizeInputFields()
        updateActionAvailability()
    }

    private func updateActionAvailability() {
        let hasAllPermissions = permissionService.hasAccessibilityPermission() && permissionService.hasScreenRecordingPermission()
        let hasModel = !modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAPIKey = !keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        requestPermissionsButton.isEnabled = !setupValidationInProgress && !hasAllPermissions
        finishSetupButton.isEnabled = !setupValidationInProgress && hasAllPermissions && hasModel && hasAPIKey
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

    private func loadSavedProviderSelection() {
        do {
            guard let selection = try appStateService.providerSelection() else {
                applySavedAPIKey(for: currentSelectedProvider())
                infoLabel.stringValue = defaultInfoMessage
                updateActionAvailability()
                return
            }
            selectProvider(selection.provider)
            modelField.stringValue = selection.model
            applySavedAPIKey(for: selection.provider)
            infoLabel.stringValue = selection.hasAPIKey
                ? "Saved setup loaded."
                : "Saved provider/model found. Add an API key to complete setup."
            updateActionAvailability()
        } catch {
            infoLabel.stringValue = defaultInfoMessage
            updateActionAvailability()
        }
    }

    private func selectProvider(_ provider: ProviderName) {
        guard
            let index = providerPopup.itemArray.firstIndex(where: {
                ($0.representedObject as? String) == provider.rawValue
            })
        else {
            return
        }
        providerPopup.selectItem(at: index)
    }

    @objc private func providerSelectionChanged() {
        guard let provider = currentSelectedProvider() else {
            return
        }
        applySavedAPIKey(for: provider)
        let hasSavedKey = !keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        infoLabel.stringValue = hasSavedKey
            ? "Saved setup loaded."
            : "No saved API key for this provider."
        updateActionAvailability()
    }

    private func currentSelectedProvider() -> ProviderName? {
        guard
            let selectedProviderRawValue = providerPopup.selectedItem?.representedObject as? String,
            let provider = ProviderName(rawValue: selectedProviderRawValue)
        else {
            return nil
        }
        return provider
    }

    private func applySavedAPIKey(for provider: ProviderName?) {
        guard let provider else {
            keyField.stringValue = ""
            return
        }
        let savedKey = (try? appStateService.apiKey(for: provider)) ?? nil
        keyField.stringValue = normalizedAPIKey(savedKey ?? "")
    }

    private func normalizeInputFields() {
        let normalizedKey = normalizedAPIKey(keyField.stringValue)
        if keyField.stringValue != normalizedKey {
            keyField.stringValue = normalizedKey
        }
    }

    private func normalizedAPIKey(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .joined()
            .trimmingCharacters(in: .whitespaces)
    }

    private func refreshPermissionsStatus() {
        let hasAllPermissions = permissionService.hasAccessibilityPermission() && permissionService.hasScreenRecordingPermission()
        requestPermissionsButton.title = hasAllPermissions ? "Permissions Granted" : "Request Permissions"
        updateActionAvailability()
    }

    private func presentSetupErrorAlert(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Setup Failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        if let window = view.window {
            alert.beginSheetModal(for: window)
            return
        }
        alert.runModal()
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
