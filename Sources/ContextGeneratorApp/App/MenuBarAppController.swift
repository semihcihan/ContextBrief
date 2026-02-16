import AppKit
import ContextGenerator
import FirebaseCrashlytics
import ServiceManagement

final class MenuBarAppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let crashlytics = Crashlytics.crashlytics()
    private let eventTracker = EventTracker.shared
    private let repository = ContextRepository()
    private lazy var sessionManager = ContextSessionManager(repository: repository)
    private let captureService = ContextCaptureService()
    private let keychain = KeychainService()
    private lazy var appStateService = AppStateService(repository: repository, keychain: keychain)
    private lazy var densificationService = DensificationService()
    private lazy var namingService = NamingService()
    private lazy var workflow = CaptureWorkflow(
        captureService: captureService,
        sessionManager: sessionManager,
        repository: repository,
        densificationService: densificationService,
        keychain: keychain
    )
    private lazy var exportService = ContextExportService(repository: repository)
    private let permissionService: PermissionServicing = PermissionService()

    private var statusItem: NSStatusItem?
    private var workspaceController: WorkspaceWindowController?
    private var statusMenuItem = NSMenuItem(title: "Status", action: nil, keyEquivalent: "")
    private var setupStatusMenuItem: NSMenuItem?
    private var completeSetupMenuItem: NSMenuItem?
    private var contextActionsHeadlineMenuItem: NSMenuItem?
    private var addSnapshotMenuItem: NSMenuItem?
    private var copyDenseMenuItem: NSMenuItem?
    private var snapshotActionsHeadlineMenuItem: NSMenuItem?
    private var undoSnapshotMenuItem: NSMenuItem?
    private var promoteSnapshotMenuItem: NSMenuItem?
    private var newContextMenuItem: NSMenuItem?
    private var separatorAfterContext: NSMenuItem?
    private var separatorAfterSetup: NSMenuItem?
    private var separatorAfterPrimary: NSMenuItem?
    private var separatorAfterActions: NSMenuItem?
    private var separatorAfterLibrary: NSMenuItem?
    private var globalHotkeyManager: GlobalHotkeyManager?
    private var areGlobalHotkeysSuspended = false
    private var isCaptureInProgress = false
    private var deferredUndoForInFlightCapture = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.debug("App launch finished. debugLoggingEnabled=\(AppLogger.debugLoggingEnabled)")
        eventTracker.track(.appReady)
        configureLaunchAtLoginIfNeeded()
        setupMainMenu()
        setupStatusItem()
        setupGlobalHotkeys()
        ensureOnboarding()
    }

    private func configureLaunchAtLoginIfNeeded() {
        do {
            let state = try appStateService.state()
            guard !state.launchAtLoginConfigured else {
                return
            }
            switch SMAppService.mainApp.status {
            case .enabled:
                AppLogger.info("Launch at login already enabled")
            case .notRegistered:
                try SMAppService.mainApp.register()
                AppLogger.info("Launch at login enabled")
            case .requiresApproval:
                AppLogger.info("Launch at login requires user approval in System Settings")
            case .notFound:
                AppLogger.error("Launch at login setup failed: app service not found")
                return
            @unknown default:
                AppLogger.error("Launch at login setup failed: unknown service status")
                return
            }
            try appStateService.markLaunchAtLoginConfigured()
        } catch {
            reportUnexpectedNonFatal(error, context: "configure_launch_at_login")
            AppLogger.error("Failed to configure launch at login: \(error.localizedDescription)")
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Context Generator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Ctx"

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        separatorAfterContext = .separator()
        if let separatorAfterContext {
            menu.addItem(separatorAfterContext)
        }

        setupStatusMenuItem = NSMenuItem(title: "Setup required", action: nil, keyEquivalent: "")
        setupStatusMenuItem?.isEnabled = false
        if let setupStatusMenuItem {
            menu.addItem(setupStatusMenuItem)
        }
        completeSetupMenuItem = addMenuItem("Complete Setup", action: #selector(openSettings), key: "", menu: menu)
        separatorAfterSetup = .separator()
        if let separatorAfterSetup {
            menu.addItem(separatorAfterSetup)
        }

        contextActionsHeadlineMenuItem = NSMenuItem(title: "Context", action: nil, keyEquivalent: "")
        contextActionsHeadlineMenuItem?.isEnabled = false
        if let contextActionsHeadlineMenuItem {
            menu.addItem(contextActionsHeadlineMenuItem)
        }
        addSnapshotMenuItem = addMenuItem("Add Snapshot to Context", action: #selector(captureContext), key: "c", indentationLevel: 1, menu: menu)
        copyDenseMenuItem = addMenuItem("Copy Current Context", action: #selector(copyDenseCurrentContext), key: "d", indentationLevel: 1, menu: menu)
        separatorAfterPrimary = .separator()
        if let separatorAfterPrimary {
            menu.addItem(separatorAfterPrimary)
        }

        snapshotActionsHeadlineMenuItem = NSMenuItem(title: "Snapshot", action: nil, keyEquivalent: "")
        snapshotActionsHeadlineMenuItem?.isEnabled = false
        if let snapshotActionsHeadlineMenuItem {
            menu.addItem(snapshotActionsHeadlineMenuItem)
        }
        undoSnapshotMenuItem = addMenuItem("Delete Last Snapshot", action: #selector(undoLastCapture), key: "", indentationLevel: 1, menu: menu)
        promoteSnapshotMenuItem = addMenuItem("Move Last Snapshot to New Context", action: #selector(promoteLastCapture), key: "", indentationLevel: 1, menu: menu)
        separatorAfterActions = .separator()
        if let separatorAfterActions {
            menu.addItem(separatorAfterActions)
        }
        newContextMenuItem = addMenuItem("Start New Context", action: #selector(startNewContext), key: "n", menu: menu)
        _ = addMenuItem("Open Context Library", action: #selector(openContextLibrary), key: "", menu: menu)
        separatorAfterLibrary = .separator()
        if let separatorAfterLibrary {
            menu.addItem(separatorAfterLibrary)
        }
        _ = addMenuItem("Settings", action: #selector(openSettings), key: "", menu: menu)
        _ = addMenuItem("Quit", action: #selector(quit), key: "", menu: menu)
        applyMenuShortcuts()

        statusItem.menu = menu
        self.statusItem = statusItem
        AppLogger.debug("Status menu configured with primary actions and sections")
        refreshMenuState()
    }

    private func addMenuItem(_ title: String, action: Selector, key: String, indentationLevel: Int = 0, menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.indentationLevel = indentationLevel
        menu.addItem(item)
        return item
    }

    private func ensureOnboarding() {
        do {
            let state = try appStateService.state()
            let setupReady = isSetupReady(state: state)
            AppLogger.debug(
                "ensureOnboarding state onboardingCompleted=\(state.onboardingCompleted) provider=\(String(describing: state.selectedProvider?.rawValue)) model=\(String(describing: state.selectedModel)) setupReady=\(setupReady)"
            )
            if setupReady {
                refreshMenuState()
                return
            }
        } catch {
            reportUnexpectedNonFatal(error, context: "ensure_onboarding")
            AppLogger.error("ensureOnboarding failed: \(error.localizedDescription)")
        }

        presentSettings(source: "onboarding")
    }

    func menuWillOpen(_ menu: NSMenu) {
        AppLogger.debug("Menu will open")
        eventTracker.track(.menuOpened)
        refreshMenuState()
    }

    private func refreshMenuState() {
        do {
            let state = try appStateService.state()
            let hasPermissions = hasAllRequiredPermissions()
            let hasProviderConfiguration = hasProviderConfiguration()
            let setupReady = isSetupReady(state: state)
            let currentContext = try sessionManager.currentContextIfExists()
            let hasSnapshotInCurrent = try (currentContext.map { context in
                try repository.lastSnapshot(in: context.id) != nil
            } ?? false)
            let lastSnapshot = try (currentContext.map { context in
                try repository.lastSnapshot(in: context.id)
            } ?? nil)
            let contextLabel = contextLabel(currentContext: currentContext, hasSnapshotInCurrent: hasSnapshotInCurrent)
            updateActionHeadlines(contextLabel: contextLabel, lastSnapshot: lastSnapshot)
            setTopStatusLine(text: isCaptureInProgress ? "Processing new snapshot..." : nil)

            if !setupReady {
                if !state.onboardingCompleted {
                    setupStatusMenuItem?.title = "Setup required: provider, model and API key"
                } else if !hasPermissions {
                    setupStatusMenuItem?.title = "Permissions required: Accessibility + Screen Recording"
                } else if !hasProviderConfiguration {
                    setupStatusMenuItem?.title = "Setup required: provider, model and API key"
                } else {
                    setupStatusMenuItem?.title = "Setup required: provider, model and API key"
                }
            } else {
                setupStatusMenuItem?.title = "Setup required"
            }
            setHidden(statusMenuItem, hidden: !isCaptureInProgress)
            setHidden(separatorAfterContext, hidden: !isCaptureInProgress)

            addSnapshotMenuItem?.isEnabled = setupReady
            undoSnapshotMenuItem?.isEnabled = hasSnapshotInCurrent || isCaptureInProgress
            promoteSnapshotMenuItem?.isEnabled = hasSnapshotInCurrent
            newContextMenuItem?.isEnabled = setupReady && hasSnapshotInCurrent
            copyDenseMenuItem?.isEnabled = hasSnapshotInCurrent
            AppLogger.debug(
                "refreshMenuState onboardingCompleted=\(state.onboardingCompleted) hasPermissions=\(hasPermissions) hasProviderConfiguration=\(hasProviderConfiguration) setupReady=\(setupReady) currentContextId=\(currentContext?.id.uuidString ?? "-") currentContextTitle=\(currentContext?.title ?? "-") hasSnapshotInCurrent=\(hasSnapshotInCurrent) captureInProgress=\(isCaptureInProgress) deferredUndo=\(deferredUndoForInFlightCapture)"
            )
            applySetupVisibility(setupReady: setupReady)
        } catch {
            reportUnexpectedNonFatal(error, context: "refresh_menu_state")
            setupStatusMenuItem?.title = "Setup required"
            setHidden(statusMenuItem, hidden: true)
            setHidden(separatorAfterContext, hidden: true)
            applySetupVisibility(setupReady: false)
            addSnapshotMenuItem?.isEnabled = false
            undoSnapshotMenuItem?.isEnabled = false
            promoteSnapshotMenuItem?.isEnabled = false
            newContextMenuItem?.isEnabled = false
            copyDenseMenuItem?.isEnabled = false
            AppLogger.error("refreshMenuState failed: \(error.localizedDescription)")
        }
    }

    private func applySetupVisibility(setupReady: Bool) {
        setHidden(setupStatusMenuItem, hidden: setupReady)
        setHidden(completeSetupMenuItem, hidden: setupReady)
        setHidden(separatorAfterSetup, hidden: setupReady)

        let hideActions = !setupReady
        setHidden(contextActionsHeadlineMenuItem, hidden: hideActions)
        setHidden(addSnapshotMenuItem, hidden: hideActions)
        setHidden(copyDenseMenuItem, hidden: hideActions)
        setHidden(separatorAfterPrimary, hidden: hideActions)
        setHidden(snapshotActionsHeadlineMenuItem, hidden: hideActions)
        setHidden(undoSnapshotMenuItem, hidden: hideActions)
        setHidden(promoteSnapshotMenuItem, hidden: hideActions)
        setHidden(separatorAfterActions, hidden: hideActions)
        setHidden(newContextMenuItem, hidden: !setupReady)
    }

    private func setHidden(_ item: NSMenuItem?, hidden: Bool) {
        item?.isHidden = hidden
    }

    private func hasAllRequiredPermissions() -> Bool {
        permissionService.hasAccessibilityPermission() && permissionService.hasScreenRecordingPermission()
    }

    private func hasProviderConfiguration() -> Bool {
        ((try? configuredModelConfig()) ?? nil) != nil
    }

    private func isSetupReady(state: AppState) -> Bool {
        state.onboardingCompleted && hasAllRequiredPermissions() && hasProviderConfiguration()
    }

    @objc private func captureContext() {
        captureFrom(source: "menu")
    }

    private func captureFrom(source: String) {
        AppLogger.debug("captureContext tapped")
        eventTracker.track(.captureRequested, parameters: ["source": source])
        if isCaptureInProgress {
            eventTracker.track(.captureBlocked, parameters: ["reason": "in_progress", "source": source])
            updateFeedback("Snapshot already processing")
            return
        }
        do {
            let state = try appStateService.state()
            guard state.onboardingCompleted else {
                AppLogger.debug("captureContext blocked: onboarding not completed")
                eventTracker.track(.captureBlocked, parameters: ["reason": "onboarding_incomplete", "source": source])
                presentSettings(source: "capture_blocked")
                return
            }
            guard permissionService.hasAccessibilityPermission(), permissionService.hasScreenRecordingPermission() else {
                AppLogger.debug("captureContext blocked: missing permissions")
                eventTracker.track(.captureBlocked, parameters: ["reason": "permissions_missing", "source": source])
                presentSettings(source: "capture_blocked")
                return
            }
            guard hasProviderConfiguration() else {
                AppLogger.debug("captureContext blocked: provider configuration missing")
                eventTracker.track(.captureBlocked, parameters: ["reason": "provider_not_configured", "source": source])
                presentSettings(source: "capture_blocked")
                return
            }
        } catch {
            reportUnexpectedNonFatal(error, context: "capture_state_check")
            AppLogger.error("captureContext state check failed: \(error.localizedDescription)")
            eventTracker.track(
                .captureFailed,
                parameters: [
                    "stage": "state_check",
                    "error": String(describing: type(of: error))
                ]
            )
            return
        }

        AppLogger.info("Capture requested")
        eventTracker.track(.captureStarted, parameters: ["source": source])
        isCaptureInProgress = true
        refreshMenuState()
        Task {
            do {
                let result = try await workflow.runCapture()
                let removedInFlight = await MainActor.run { [weak self] in
                    self?.consumeDeferredUndoAfterCapture() ?? false
                }
                if removedInFlight {
                    await MainActor.run { [weak self] in
                        self?.isCaptureInProgress = false
                        self?.refreshMenuState()
                    }
                    AppLogger.info("Capture discarded due to deferred undo")
                    return
                }
                AppLogger.debug("captureContext success snapshotId=\(result.snapshot.id.uuidString) contextId=\(result.context.id.uuidString)")
                eventTracker.track(.captureSucceeded, parameters: ["sequence": result.snapshot.sequence])
                updateFeedback("Snapshot added to \(result.context.title)")
                await applyGeneratedNames(result)
                await MainActor.run { [weak self] in
                    self?.isCaptureInProgress = false
                    self?.refreshMenuState()
                }
                AppLogger.info("Capture complete snapshot=\(result.snapshot.id.uuidString)")
            } catch {
                reportUnexpectedNonFatal(error, context: "capture_workflow")
                await MainActor.run { [weak self] in
                    self?.isCaptureInProgress = false
                    self?.deferredUndoForInFlightCapture = false
                }
                if let appError = error as? AppError {
                    switch appError {
                    case .providerRequestFailed(let details):
                        updateFeedback("Model request failed: \(details)")
                    default:
                        updateFeedback("Snapshot failed: \(appError.localizedDescription)")
                    }
                } else {
                    updateFeedback("Snapshot failed: \(error.localizedDescription)")
                }
                eventTracker.track(
                    .captureFailed,
                    parameters: [
                        "stage": "workflow",
                        "error": analyticsErrorCode(error)
                    ]
                )
                AppLogger.error("Capture failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func undoLastCapture() {
        AppLogger.debug("undoLastCapture tapped")
        eventTracker.track(.undoRequested)
        if isCaptureInProgress {
            deferredUndoForInFlightCapture = true
            updateFeedback("Will remove processing snapshot when ready")
            refreshMenuState()
            eventTracker.track(.undoRequested, parameters: ["mode": "deferred"])
            AppLogger.info("undoLastCapture queued for in-flight capture")
            return
        }
        guard hasSnapshotsInCurrentContext() else {
            updateFeedback("No snapshot to move")
            refreshMenuState()
            return
        }
        do {
            let removed = try sessionManager.undoLastCaptureInCurrentContext()
            eventTracker.track(.undoSucceeded, parameters: ["snapshot_id": removed.id.uuidString])
            updateFeedback("Moved \(removed.title) to trash")
            refreshMenuState()
        } catch {
            reportUnexpectedNonFatal(error, context: "undo_last_capture")
            eventTracker.track(.undoFailed, parameters: ["error": analyticsErrorCode(error)])
            AppLogger.error("undoLastCapture failed: \(error.localizedDescription)")
            updateFeedback("Undo failed")
        }
    }

    @objc private func promoteLastCapture() {
        AppLogger.debug("promoteLastCapture tapped")
        eventTracker.track(.promoteRequested)
        guard hasSnapshotsInCurrentContext() else {
            updateFeedback("No snapshot to move")
            refreshMenuState()
            return
        }
        do {
            let context = try sessionManager.promoteLastCaptureToNewContext()
            eventTracker.track(.promoteSucceeded, parameters: ["context_id": context.id.uuidString])
            AppLogger.debug("promoteLastCapture success newContextId=\(context.id.uuidString) title=\(context.title)")
            updateFeedback("Moved last snapshot to new context")
            refreshMenuState()
            Task {
                await applyGeneratedContextName(contextId: context.id, fallback: context.title)
                await MainActor.run { [weak self] in
                    self?.refreshMenuState()
                }
            }
        } catch {
            reportUnexpectedNonFatal(error, context: "promote_last_capture")
            eventTracker.track(.promoteFailed, parameters: ["error": analyticsErrorCode(error)])
            AppLogger.error("promoteLastCapture failed: \(error.localizedDescription)")
            updateFeedback("Move failed")
        }
    }

    @objc private func startNewContext() {
        AppLogger.debug("startNewContext tapped")
        eventTracker.track(.newContextRequested)
        guard hasSnapshotsInCurrentContext() else {
            updateFeedback("Current context is already empty")
            refreshMenuState()
            return
        }
        do {
            let context = try sessionManager.createNewContext(title: "New Context")
            eventTracker.track(.newContextSucceeded, parameters: ["context_id": context.id.uuidString])
            AppLogger.debug("startNewContext success contextId=\(context.id.uuidString)")
            updateFeedback("Started a new context")
            refreshMenuState()
        } catch {
            reportUnexpectedNonFatal(error, context: "start_new_context")
            eventTracker.track(.newContextFailed, parameters: ["error": analyticsErrorCode(error)])
            AppLogger.error("startNewContext failed: \(error.localizedDescription)")
            updateFeedback("New context failed")
        }
    }

    @objc private func openContextLibrary() {
        eventTracker.track(.contextLibraryOpened, parameters: ["source": "menu"])
        workspaceWindowController().show(section: .contextLibrary, sender: self)
    }

    @objc private func copyDenseCurrentContext() {
        copyDenseCurrentContextFrom(source: "menu")
    }

    private func copyDenseCurrentContextFrom(source: String) {
        AppLogger.debug("copyDenseCurrentContext tapped")
        eventTracker.track(
            .copyContextRequested,
            parameters: [
                "mode": "dense",
                "source": source
            ]
        )
        guard hasSnapshotsInCurrentContext() else {
            updateFeedback("Nothing to copy yet")
            refreshMenuState()
            return
        }
        copyCurrentContext(mode: .dense)
    }

    private func copyCurrentContext(mode: ExportMode) {
        do {
            let context = try sessionManager.currentContext()
            let text = try exportService.exportText(contextId: context.id, mode: mode)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            eventTracker.track(
                .copyContextSucceeded,
                parameters: [
                    "mode": analyticsExportModeName(mode),
                    "length": text.count
                ]
            )
            AppLogger.debug("copyCurrentContext success contextId=\(context.id.uuidString) mode=dense chars=\(text.count)")
            updateFeedback("Copied dense context")
        } catch {
            reportUnexpectedNonFatal(error, context: "copy_current_context")
            eventTracker.track(
                .copyContextFailed,
                parameters: [
                    "mode": analyticsExportModeName(mode),
                    "error": analyticsErrorCode(error)
                ]
            )
            AppLogger.error("copyCurrentContext failed: \(error.localizedDescription)")
            updateFeedback("Copy failed")
            AppLogger.error("Copy failed: \(error.localizedDescription)")
        }
    }

    @objc private func openSettings() {
        presentSettings(source: "menu")
    }

    private func presentSettings(source: String) {
        eventTracker.track(.settingsOpened, parameters: ["source": source])
        workspaceWindowController().show(section: .setup, sender: self)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func updateFeedback(_ text: String) {
        DispatchQueue.main.async {
            self.statusItem?.button?.toolTip = text
        }
    }

    private func workspaceWindowController() -> WorkspaceWindowController {
        if let workspaceController {
            return workspaceController
        }
        let created = WorkspaceWindowController(
            permissionService: permissionService,
            appStateService: appStateService,
            repository: repository,
            sessionManager: sessionManager,
            onSetupComplete: { [weak self] in
                self?.updateFeedback("Setup complete")
                self?.refreshMenuState()
            },
            onShortcutsUpdated: { [weak self] in
                self?.updateShortcutBindings() ?? []
            },
            onShortcutRecordingStateChanged: { [weak self] isRecording in
                self?.setGlobalHotkeysSuspended(isRecording)
            },
            onSelectionChange: { [weak self] text in
                self?.updateFeedback(text)
                self?.refreshMenuState()
            }
        )
        workspaceController = created
        return created
    }

    private func consumeDeferredUndoAfterCapture() -> Bool {
        guard deferredUndoForInFlightCapture else {
            return false
        }
        deferredUndoForInFlightCapture = false
        do {
            let removed = try sessionManager.undoLastCaptureInCurrentContext()
            updateFeedback("Moved \(removed.title) to trash")
            return true
        } catch {
            reportUnexpectedNonFatal(error, context: "deferred_undo_after_capture")
            AppLogger.error("Deferred undo failed: \(error.localizedDescription)")
            updateFeedback("Undo failed")
            return false
        }
    }

    private func contextLabel(currentContext: Context?, hasSnapshotInCurrent: Bool) -> String {
        guard let currentContext else {
            return "New Context"
        }
        return hasSnapshotInCurrent ? currentContext.title : "Empty Context"
    }

    private func hasSnapshotsInCurrentContext() -> Bool {
        guard
            let context = ((try? sessionManager.currentContextIfExists()) ?? nil),
            let hasSnapshot = try? repository.lastSnapshot(in: context.id) != nil
        else {
            return false
        }
        return hasSnapshot
    }

    private func updateActionHeadlines(contextLabel: String, lastSnapshot: Snapshot?) {
        let snapshotPreview = snapshotPreviewText(snapshot: lastSnapshot)
        let snapshotLabel = isCaptureInProgress ? "Processing..." : snapshotPreview
        applyHeadline(
            item: contextActionsHeadlineMenuItem,
            title: contextLabel
        )
        applyHeadline(
            item: snapshotActionsHeadlineMenuItem,
            title: snapshotLabel
        )
    }

    private func snapshotPreviewText(snapshot: Snapshot?) -> String {
        guard let snapshot else {
            return "No Snapshots"
        }
        let normalized = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return "Untitled Snapshot"
        }
        let words = normalized.split(separator: " ")
        let excerpt = words.prefix(6).joined(separator: " ")
        if excerpt.count < normalized.count {
            return "\(excerpt)..."
        }
        return excerpt
    }

    private func setTopStatusLine(text: String?) {
        guard let text else {
            statusMenuItem.attributedTitle = nil
            return
        }
        statusMenuItem.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        )
    }

    private func applyHeadline(item: NSMenuItem?, title: String) {
        guard let item else {
            return
        }
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: NSColor.labelColor]
        )
    }

    private struct ModelConfig {
        let provider: ProviderName
        let model: String
        let apiKey: String
    }

    private func configuredModelConfig(forTitleGeneration: Bool = false) throws -> ModelConfig? {
        let developmentConfig = DevelopmentConfig.shared
        let state = try appStateService.state()
        guard let selectedProvider = state.selectedProvider else {
            AppLogger.debug("configuredModelConfig unavailable: provider/model missing")
            return nil
        }
        let provider = forTitleGeneration
            ? developmentConfig.providerForTitleGeneration(selectedProvider: selectedProvider)
            : developmentConfig.providerForDensification(selectedProvider: selectedProvider)
        let model = state.selectedModel ?? ""
        guard provider == .apple || !model.isEmpty else {
            AppLogger.debug("configuredModelConfig unavailable: model missing for provider=\(provider.rawValue)")
            return nil
        }
        let apiKey = try keychain.get("api.\(provider.rawValue)") ?? ""
        guard provider == .apple || !apiKey.isEmpty else {
            AppLogger.debug("configuredModelConfig unavailable: key missing for provider=\(provider.rawValue)")
            return nil
        }
        AppLogger.debug(
            "configuredModelConfig available selectedProvider=\(selectedProvider.rawValue) effectiveProvider=\(provider.rawValue) model=\(model)"
        )
        return ModelConfig(provider: provider, model: model, apiKey: apiKey)
    }

    private func applyGeneratedNames(_ result: CaptureWorkflowResult) async {
        guard let config = ((try? configuredModelConfig(forTitleGeneration: true)) ?? nil) else {
            AppLogger.debug("applyGeneratedNames skipped: model config unavailable")
            return
        }

        let snapshotTitle = await namingService.suggestSnapshotTitle(
            capturedSnapshot: result.capturedSnapshot,
            denseContent: result.snapshot.denseContent,
            provider: config.provider,
            model: config.model,
            apiKey: config.apiKey,
            fallback: result.snapshot.title
        )

        do {
            let snapshot = try sessionManager.renameSnapshot(result.snapshot.id, title: snapshotTitle)
            AppLogger.debug("applyGeneratedNames snapshot title updated snapshotId=\(snapshot.id.uuidString) title=\(snapshot.title)")
        } catch {}

        if result.snapshot.sequence == 1 {
            _ = try? sessionManager.renameContext(result.context.id, title: snapshotTitle)
            AppLogger.debug(
                "applyGeneratedNames context title set from first snapshot contextId=\(result.context.id.uuidString) title=\(snapshotTitle)"
            )
            return
        }

        let refreshEvery = DevelopmentConfig.shared.contextTitleRefreshEvery(for: config.provider)
        guard result.snapshot.sequence % refreshEvery == 0 else {
            AppLogger.debug(
                "applyGeneratedNames context title skipped sequence=\(result.snapshot.sequence) contextId=\(result.context.id.uuidString) refreshEvery=\(refreshEvery) provider=\(config.provider.rawValue)"
            )
            return
        }

        await applyGeneratedContextName(contextId: result.context.id, fallback: result.context.title)
    }

    private func applyGeneratedContextName(contextId: UUID, fallback: String) async {
        guard let config = ((try? configuredModelConfig(forTitleGeneration: true)) ?? nil) else {
            AppLogger.debug("applyGeneratedContextName skipped: model config unavailable")
            return
        }
        guard
            let context = ((try? repository.context(id: contextId)) ?? nil),
            let snapshots = try? repository.snapshots(in: contextId),
            !snapshots.isEmpty
        else {
            AppLogger.debug("applyGeneratedContextName skipped: no context/snapshots for contextId=\(contextId.uuidString)")
            return
        }

        let title = await namingService.suggestContextTitle(
            snapshots: snapshots,
            provider: config.provider,
            model: config.model,
            apiKey: config.apiKey,
            fallback: fallback
        )
        _ = try? sessionManager.renameContext(contextId, title: title)
        AppLogger.debug("applyGeneratedContextName updated contextId=\(contextId.uuidString) oldTitle=\(context.title) newTitle=\(title)")
    }

    private func setupGlobalHotkeys() {
        globalHotkeyManager = GlobalHotkeyManager { [weak self] action in
            guard let self else {
                return
            }
            DispatchQueue.main.async {
                self.eventTracker.track(.hotkeyTriggered, parameters: ["action": self.analyticsHotkeyActionName(action)])
                switch action {
                case .addSnapshot:
                    self.captureFrom(source: "hotkey")
                case .copyCurrentContext:
                    self.copyDenseCurrentContextFrom(source: "hotkey")
                }
            }
        }
        _ = updateShortcutBindings()
    }

    private func updateShortcutBindings() -> [String] {
        applyMenuShortcuts()
        return configureGlobalHotkeys()
    }

    private func configureGlobalHotkeys() -> [String] {
        guard let globalHotkeyManager else {
            return []
        }
        let shortcuts = (try? appStateService.shortcuts()) ?? .defaultValue
        let failed = globalHotkeyManager.apply(shortcuts: shortcuts)
        let labels = failed.map {
            switch $0 {
            case .addSnapshot:
                return "Add Snapshot"
            case .copyCurrentContext:
                return "Copy Current Context"
            }
        }
        guard !labels.isEmpty else {
            return []
        }
        eventTracker.track(
            .shortcutRegistrationFailed,
            parameters: [
                "count": labels.count,
                "labels": labels.joined(separator: ",")
            ]
        )
        updateFeedback("Shortcut unavailable: \(labels.joined(separator: ", "))")
        return labels
    }

    private func setGlobalHotkeysSuspended(_ suspended: Bool) {
        guard let globalHotkeyManager else {
            return
        }
        guard areGlobalHotkeysSuspended != suspended else {
            return
        }
        areGlobalHotkeysSuspended = suspended
        let failed = globalHotkeyManager.setSuspended(suspended)
        guard !failed.isEmpty else {
            return
        }
        let labels = failed.map {
            switch $0 {
            case .addSnapshot:
                return "Add Snapshot"
            case .copyCurrentContext:
                return "Copy Current Context"
            }
        }
        updateFeedback("Shortcut unavailable: \(labels.joined(separator: ", "))")
    }

    private func analyticsHotkeyActionName(_ action: GlobalHotkeyManager.Action) -> String {
        switch action {
        case .addSnapshot:
            return "add_snapshot"
        case .copyCurrentContext:
            return "copy_current_context"
        }
    }

    private func analyticsExportModeName(_ mode: ExportMode) -> String {
        switch mode {
        case .dense:
            return "dense"
        }
    }

    private func analyticsErrorCode(_ error: Error) -> String {
        guard let appError = error as? AppError else {
            return String(describing: type(of: error))
        }
        switch appError {
        case .noFrontmostApp:
            return "no_frontmost_app"
        case .noCurrentContext:
            return "no_current_context"
        case .noCaptureToUndo:
            return "no_capture_to_undo"
        case .noCaptureToPromote:
            return "no_capture_to_promote"
        case .contextNotFound:
            return "context_not_found"
        case .snapshotNotFound:
            return "snapshot_not_found"
        case .keyNotConfigured:
            return "key_not_configured"
        case .providerNotConfigured:
            return "provider_not_configured"
        case .providerRequestFailed:
            return "provider_request_failed"
        }
    }

    private func reportUnexpectedNonFatal(_ error: Error, context: String) {
        guard (error as? AppError) == nil else {
            return
        }
        crashlytics.setCustomValue(context, forKey: "nonfatal_context")
        crashlytics.record(error: error)
    }

    private func applyMenuShortcuts() {
        let shortcuts = (try? appStateService.shortcuts()) ?? .defaultValue
        applyMenuShortcut(item: addSnapshotMenuItem, binding: shortcuts.addSnapshot)
        applyMenuShortcut(item: copyDenseMenuItem, binding: shortcuts.copyCurrentContext)
    }

    private func applyMenuShortcut(item: NSMenuItem?, binding: ShortcutBinding) {
        guard let item else {
            return
        }
        item.keyEquivalent = ShortcutKeyOptions.keyEquivalent(for: binding.keyCode)
        var mask: NSEvent.ModifierFlags = []
        if binding.command {
            mask.insert(.command)
        }
        if binding.option {
            mask.insert(.option)
        }
        if binding.control {
            mask.insert(.control)
        }
        if binding.shift {
            mask.insert(.shift)
        }
        item.keyEquivalentModifierMask = mask
    }
}
