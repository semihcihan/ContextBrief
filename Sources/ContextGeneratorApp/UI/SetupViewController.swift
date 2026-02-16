import AppKit
import ContextGenerator
import ServiceManagement

final class SetupViewController: NSViewController, NSTextFieldDelegate {

    private struct SetupSnapshot: Equatable {
        let provider: ProviderName?
        let model: String
        let apiKey: String
    }

    private let permissionService: PermissionServicing
    private let appStateService: AppStateService
    private let developmentConfig: DevelopmentConfig
    private let onComplete: () -> Void

    private let providerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let modelField = NSTextField(string: "gpt-5-nano")
    private let keyField = NSSecureTextField(frame: .zero)
    private let infoLabel = NSTextField(labelWithString: "")
    private let validationSpinner = NSProgressIndicator()
    private let statusBalanceSpacer = NSView()
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let requestPermissionsButton = NSButton(title: "Request Permissions", target: nil, action: nil)
    private let finishSetupButton = NSButton(title: "Finish Setup", target: nil, action: nil)
    private let setupCompleteBadge = NSTextField(labelWithString: "Setup complete")
    private var setupValidationInProgress = false
    private var initialSnapshot: SetupSnapshot?
    private var onboardingCompletedAtLoad = false
    private let defaultInfoMessage = "Accessibility + Screen Recording are required."

    init(
        permissionService: PermissionServicing,
        appStateService: AppStateService,
        developmentConfig: DevelopmentConfig = .shared,
        onComplete: @escaping () -> Void
    ) {
        self.permissionService = permissionService
        self.appStateService = appStateService
        self.developmentConfig = developmentConfig
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
        refreshLaunchAtLoginCheckbox()
        refreshPermissionsStatus()
        loadSavedProviderSelection()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshLaunchAtLoginCheckbox()
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
        for provider in availableProviders() {
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
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin)
        stack.addArrangedSubview(launchAtLoginCheckbox)
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
        stack.setCustomSpacing(6, after: buttonColumn)

        setupCompleteBadge.alignment = .center
        setupCompleteBadge.textColor = .secondaryLabelColor
        setupCompleteBadge.font = .systemFont(ofSize: 11, weight: .medium)
        setupCompleteBadge.isHidden = true
        stack.addArrangedSubview(setupCompleteBadge)
        stack.setCustomSpacing(12, after: setupCompleteBadge)

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
        updateProviderFieldAvailability()
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
        let requiresCredentials = providerRequiresCredentials(provider)
        guard !requiresCredentials || !model.isEmpty else {
            infoLabel.stringValue = "Model is required."
            return
        }

        let apiKeyForValidation = normalizedAPIKey(keyField.stringValue)
        keyField.stringValue = apiKeyForValidation
        infoLabel.stringValue = "Validating model access..."
        guard !requiresCredentials || !apiKeyForValidation.isEmpty else {
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
                    model: requiresCredentials ? model : "",
                    apiKey: requiresCredentials ? apiKeyForValidation : nil
                )
                try self.appStateService.markOnboardingCompleted()
                await MainActor.run {
                    self.setValidationInProgress(false)
                    self.onboardingCompletedAtLoad = true
                    self.initialSnapshot = self.currentSnapshot()
                    self.updateActionAvailability()
                    self.infoLabel.stringValue = ""
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

    @objc private func toggleLaunchAtLogin() {
        let shouldEnable = launchAtLoginCheckbox.state == .on
        do {
            if shouldEnable {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                    try SMAppService.mainApp.unregister()
                }
            }
            try appStateService.markLaunchAtLoginConfigured()
            refreshLaunchAtLoginCheckbox()
        } catch {
            refreshLaunchAtLoginCheckbox()
            infoLabel.stringValue = "Could not update launch at login."
        }
    }

    private func setValidationInProgress(_ inProgress: Bool) {
        setupValidationInProgress = inProgress
        providerPopup.isEnabled = !inProgress
        updateProviderFieldAvailability()
        if inProgress {
            validationSpinner.startAnimation(nil)
            finishSetupButton.title = "Validating..."
            return
        }
        validationSpinner.stopAnimation(nil)
        updateFinishSetupButtonTitle()
    }

    @objc private func inputFieldsChanged() {
        updateActionAvailability()
    }

    func controlTextDidChange(_ notification: Notification) {
        normalizeInputFields()
        updateActionAvailability()
    }

    private func updateActionAvailability() {
        let hasAllPermissions = hasAllPermissions()
        let providerReady = providerConfigurationReady()
        let configurationDirty = isConfigurationDirty()
        requestPermissionsButton.isEnabled = !setupValidationInProgress && !hasAllPermissions
        finishSetupButton.isEnabled = !setupValidationInProgress &&
            hasAllPermissions &&
            providerReady &&
            (!onboardingCompletedAtLoad || configurationDirty)
        if !setupValidationInProgress {
            updateFinishSetupButtonTitle()
        }
        updateSetupCompleteBadgeVisibility(
            hasAllPermissions: hasAllPermissions,
            providerReady: providerReady,
            configurationDirty: configurationDirty
        )
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
            let state = try appStateService.state()
            onboardingCompletedAtLoad = state.onboardingCompleted
            guard let selection = try appStateService.providerSelection() else {
                applySavedModelAndAPIKey(for: currentSelectedProvider())
                initialSnapshot = currentSnapshot()
                updateInfoLabelForLoadedState(selection: nil)
                updateProviderFieldAvailability()
                updateActionAvailability()
                return
            }
            selectProvider(selection.provider)
            applySavedModelAndAPIKey(for: selection.provider, fallbackModel: selection.model)
            initialSnapshot = currentSnapshot()
            updateInfoLabelForLoadedState(selection: selection)
            updateProviderFieldAvailability()
            updateActionAvailability()
        } catch {
            onboardingCompletedAtLoad = false
            initialSnapshot = currentSnapshot()
            infoLabel.stringValue = defaultInfoMessage
            updateProviderFieldAvailability()
            updateActionAvailability()
        }
    }

    private func availableProviders() -> [ProviderName] {
        let providers: [ProviderName] = [.openai, .anthropic, .gemini]
        guard developmentConfig.appleFoundationProviderEnabled else {
            return providers
        }
        return providers + [.apple]
    }

    private func providerRequiresCredentials(_ provider: ProviderName) -> Bool {
        provider != .apple
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
        applySavedModelAndAPIKey(for: provider, fallbackModel: "")
        updateProviderFieldAvailability()
        if providerRequiresCredentials(provider) {
            let hasModel = !normalizedModel(modelField.stringValue).isEmpty
            let hasAPIKey = !normalizedAPIKey(keyField.stringValue).isEmpty
            if hasModel && hasAPIKey {
                infoLabel.stringValue = onboardingCompletedAtLoad ? "" : "Ready to finish setup."
                updateActionAvailability()
                return
            }
            infoLabel.stringValue = onboardingCompletedAtLoad
                ? "Enter model and API key to save changes."
                : "Enter model and API key to complete setup."
            updateActionAvailability()
            return
        }
        infoLabel.stringValue = onboardingCompletedAtLoad
            ? ""
            : "Apple Foundation selected. Model and API key are not required."
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

    private func applySavedModelAndAPIKey(for provider: ProviderName?, fallbackModel: String? = nil) {
        guard let provider else {
            modelField.stringValue = fallbackModel ?? modelField.stringValue
            keyField.stringValue = ""
            return
        }
        let savedModel = (try? appStateService.model(for: provider)) ?? fallbackModel ?? modelField.stringValue
        if providerRequiresCredentials(provider) {
            modelField.stringValue = savedModel
            let savedKey = (try? appStateService.apiKey(for: provider)) ?? nil
            keyField.stringValue = normalizedAPIKey(savedKey ?? "")
            return
        }
        modelField.stringValue = ""
        keyField.stringValue = ""
    }

    private func updateProviderFieldAvailability() {
        let enabled = !setupValidationInProgress
        let requiresCredentials = currentSelectedProvider().map(providerRequiresCredentials) ?? true
        modelField.isEnabled = enabled && requiresCredentials
        modelField.isEditable = enabled && requiresCredentials
        keyField.isEnabled = enabled && requiresCredentials
        keyField.isEditable = enabled && requiresCredentials
        if requiresCredentials {
            modelField.placeholderString = "gpt-5-nano"
            keyField.placeholderString = ""
            return
        }
        modelField.placeholderString = "Not required for Apple Foundation"
        keyField.placeholderString = "Not required for Apple Foundation"
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

    private func normalizedModel(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func hasAllPermissions() -> Bool {
        permissionService.hasAccessibilityPermission() && permissionService.hasScreenRecordingPermission()
    }

    private func providerConfigurationReady() -> Bool {
        let requiresCredentials = currentSelectedProvider().map(providerRequiresCredentials) ?? true
        if !requiresCredentials {
            return true
        }
        let hasModel = !normalizedModel(modelField.stringValue).isEmpty
        let hasAPIKey = !normalizedAPIKey(keyField.stringValue).isEmpty
        return hasModel && hasAPIKey
    }

    private func currentSnapshot() -> SetupSnapshot {
        SetupSnapshot(
            provider: currentSelectedProvider(),
            model: normalizedModel(modelField.stringValue),
            apiKey: normalizedAPIKey(keyField.stringValue)
        )
    }

    private func isConfigurationDirty() -> Bool {
        guard let initialSnapshot else {
            return false
        }
        return currentSnapshot() != initialSnapshot
    }

    private func updateFinishSetupButtonTitle() {
        finishSetupButton.title = onboardingCompletedAtLoad ? "Save Changes" : "Finish Setup"
    }

    private func updateSetupCompleteBadgeVisibility(
        hasAllPermissions: Bool,
        providerReady: Bool,
        configurationDirty: Bool
    ) {
        setupCompleteBadge.isHidden = !(onboardingCompletedAtLoad && hasAllPermissions && providerReady && !configurationDirty)
    }

    private func updateInfoLabelForLoadedState(selection: AppStateService.ProviderSelection?) {
        guard hasAllPermissions() else {
            infoLabel.stringValue = defaultInfoMessage
            return
        }
        guard let selection else {
            infoLabel.stringValue = onboardingCompletedAtLoad ? "" : "Select provider, model, and API key to complete setup."
            return
        }
        if providerRequiresCredentials(selection.provider) {
            infoLabel.stringValue = selection.hasAPIKey
                ? (onboardingCompletedAtLoad ? "" : "Ready to finish setup.")
                : "Saved provider/model found. Add an API key to complete setup."
            return
        }
        infoLabel.stringValue = onboardingCompletedAtLoad
            ? ""
            : "Apple Foundation selected. Model and API key are not required."
    }

    private func refreshPermissionsStatus() {
        let hasAllPermissions = hasAllPermissions()
        requestPermissionsButton.title = hasAllPermissions ? "Permissions Granted" : "Request Permissions"
        updateActionAvailability()
    }

    private func refreshLaunchAtLoginCheckbox() {
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
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

    func testingProviderTitles() -> [String] {
        providerPopup.itemArray.map(\.title)
    }

    func testingSelectProvider(_ provider: ProviderName) {
        selectProvider(provider)
        providerSelectionChanged()
    }

    func testingSelectedProvider() -> ProviderName? {
        currentSelectedProvider()
    }

    func testingModelFieldEnabled() -> Bool {
        modelField.isEnabled && modelField.isEditable
    }

    func testingKeyFieldEnabled() -> Bool {
        keyField.isEnabled && keyField.isEditable
    }

    func testingModelValue() -> String {
        modelField.stringValue
    }

    func testingAPIKeyValue() -> String {
        keyField.stringValue
    }

    func testingInfoLabelValue() -> String {
        infoLabel.stringValue
    }

    func testingFinishSetupButtonTitle() -> String {
        finishSetupButton.title
    }

    func testingFinishSetupButtonEnabled() -> Bool {
        finishSetupButton.isEnabled
    }

    func testingSetupCompleteBadgeVisible() -> Bool {
        !setupCompleteBadge.isHidden
    }

    func testingSetModelValue(_ value: String) {
        modelField.stringValue = value
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    }

    func testingSetAPIKeyValue(_ value: String) {
        keyField.stringValue = value
        controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
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
        case .apple:
            return "Apple Foundation"
        }
    }
}
