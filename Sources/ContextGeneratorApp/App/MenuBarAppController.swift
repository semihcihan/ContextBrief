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
    private lazy var snapshotRetryWorkflow = SnapshotRetryWorkflow(
        repository: repository,
        densificationService: densificationService,
        keychain: keychain
    )
    private lazy var workflow = CaptureWorkflow(
        sessionManager: sessionManager,
        repository: repository,
        densificationService: densificationService,
        keychain: keychain
    )
    private lazy var snapshotProcessingCoordinator = SnapshotProcessingCoordinator(
        captureService: captureService,
        captureWorkflow: workflow,
        retryWorkflow: snapshotRetryWorkflow,
        sessionManager: sessionManager,
        repository: repository
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
    private var retryFailedSnapshotsMenuItem: NSMenuItem?
    private var newContextMenuItem: NSMenuItem?
    private var separatorAfterContext: NSMenuItem?
    private var separatorAfterSetup: NSMenuItem?
    private var separatorAfterPrimary: NSMenuItem?
    private var separatorAfterActions: NSMenuItem?
    private var separatorAfterLibrary: NSMenuItem?
    private var checkForUpdatesMenuItem: NSMenuItem?
    private var globalHotkeyManager: GlobalHotkeyManager?
    private var areGlobalHotkeysSuspended = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.debug("App launch finished. debugLoggingEnabled=\(AppLogger.debugLoggingEnabled)")
        eventTracker.track(.appReady)
        snapshotProcessingCoordinator.delegate = self
        configureLaunchAtLoginIfNeeded()
        setupMainMenu()
        setupStatusItem()
        setupGlobalHotkeys()
        ensureOnboarding()
        UpdateChecker.shared.checkForUpdates(silent: true)
    }

    private func configureLaunchAtLoginIfNeeded() {
        do {
            let state = try appStateService.state()
            guard !state.launchAtLoginConfigured else {
                return
            }
            switch SMAppService.mainApp.status {
            case .enabled:
                AppLogger.debug("Launch at login already enabled")
            case .notRegistered:
                try SMAppService.mainApp.register()
                AppLogger.debug("Launch at login enabled")
            case .requiresApproval:
                AppLogger.debug("Launch at login requires user approval in System Settings")
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
        appMenu.addItem(withTitle: "Quit Context Brief", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        retryFailedSnapshotsMenuItem = addMenuItem("Retry Failed Snapshot", action: #selector(retryFailedSnapshots), key: "", indentationLevel: 1, menu: menu)
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
        checkForUpdatesMenuItem = addMenuItem("Check for Updates...", action: #selector(checkForUpdates), key: "", menu: menu)
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
            let snapshotsInCurrent = try (currentContext.map { context in
                try repository.snapshots(in: context.id)
            } ?? [])
            let hasSnapshotInCurrent = !snapshotsInCurrent.isEmpty
            let lastSnapshot = snapshotsInCurrent.last
            let failedSnapshotCount = snapshotsInCurrent.filter { $0.status == .failed }.count
            let contextLabel = contextLabel(currentContext: currentContext, hasSnapshotInCurrent: hasSnapshotInCurrent)
            updateActionHeadlines(contextLabel: contextLabel, lastSnapshot: lastSnapshot)
            statusItem?.button?.title = statusItemTitle()
            setTopStatusLine(text: processingStatusText())

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
            setHidden(statusMenuItem, hidden: !isAnyProcessing)
            setHidden(separatorAfterContext, hidden: !isAnyProcessing)

            addSnapshotMenuItem?.isEnabled = setupReady
            undoSnapshotMenuItem?.isEnabled = (hasSnapshotInCurrent || isCaptureInProgress) && !isAnyProcessing
            promoteSnapshotMenuItem?.isEnabled = hasSnapshotInCurrent && !isAnyProcessing
            retryFailedSnapshotsMenuItem?.isEnabled = setupReady && failedSnapshotCount > 0 && !isAnyProcessing
            retryFailedSnapshotsMenuItem?.title = failedSnapshotCount > 1
                ? "Retry Failed Snapshots (\(failedSnapshotCount))"
                : "Retry Failed Snapshot"
            newContextMenuItem?.isEnabled = setupReady && (hasSnapshotInCurrent || isCaptureInProgress)
            copyDenseMenuItem?.isEnabled = hasSnapshotInCurrent && !isAnyProcessing
            AppLogger.debug(
                "refreshMenuState onboardingCompleted=\(state.onboardingCompleted) hasPermissions=\(hasPermissions) hasProviderConfiguration=\(hasProviderConfiguration) setupReady=\(setupReady) currentContextId=\(currentContext?.id.uuidString ?? "-") currentContextTitle=\(currentContext?.title ?? "-") hasSnapshotInCurrent=\(hasSnapshotInCurrent) failedSnapshots=\(failedSnapshotCount) captureInProgress=\(isCaptureInProgress) activeRetryOperations=\(snapshotProcessingCoordinator.activeRetryCount) queuedCaptures=\(snapshotProcessingCoordinator.queuedCaptureCount)"
            )
            applySetupVisibility(setupReady: setupReady)
            setHidden(retryFailedSnapshotsMenuItem, hidden: !setupReady || failedSnapshotCount == 0)
        } catch {
            reportUnexpectedNonFatal(error, context: "refresh_menu_state")
            setupStatusMenuItem?.title = "Setup required"
            setHidden(statusMenuItem, hidden: true)
            setHidden(separatorAfterContext, hidden: true)
            applySetupVisibility(setupReady: false)
            addSnapshotMenuItem?.isEnabled = false
            undoSnapshotMenuItem?.isEnabled = false
            promoteSnapshotMenuItem?.isEnabled = false
            retryFailedSnapshotsMenuItem?.isEnabled = false
            setHidden(retryFailedSnapshotsMenuItem, hidden: true)
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
        setHidden(retryFailedSnapshotsMenuItem, hidden: hideActions)
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

        guard canCapture(source: source) else {
            refreshMenuState()
            return
        }
        snapshotProcessingCoordinator.requestCapture(source: source)
    }

    private func canCapture(source: String) -> Bool {
        do {
            let state = try appStateService.state()
            guard state.onboardingCompleted else {
                AppLogger.debug("captureContext blocked: onboarding not completed")
                eventTracker.track(.captureBlocked, parameters: ["reason": "onboarding_incomplete", "source": source])
                presentSettings(source: "capture_blocked")
                return false
            }
            guard permissionService.hasAccessibilityPermission(), permissionService.hasScreenRecordingPermission() else {
                AppLogger.debug("captureContext blocked: missing permissions")
                eventTracker.track(.captureBlocked, parameters: ["reason": "permissions_missing", "source": source])
                presentSettings(source: "capture_blocked")
                return false
            }
            guard hasProviderConfiguration() else {
                AppLogger.debug("captureContext blocked: provider configuration missing")
                eventTracker.track(.captureBlocked, parameters: ["reason": "provider_not_configured", "source": source])
                presentSettings(source: "capture_blocked")
                return false
            }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                AppLogger.debug("captureContext blocked: app itself is frontmost")
                eventTracker.track(.captureBlocked, parameters: ["reason": "self_frontmost", "source": source])
                return false
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
            return false
        }
        return true
    }

    @objc private func undoLastCapture() {
        AppLogger.debug("undoLastCapture tapped")
        eventTracker.track(.undoRequested)
        guard !isAnyProcessing else {
            updateFeedback("Please wait for current processing to finish")
            refreshMenuState()
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
        guard !isAnyProcessing else {
            updateFeedback("Please wait for current processing to finish")
            refreshMenuState()
            return
        }
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

    @objc private func retryFailedSnapshots() {
        guard !isAnyProcessing else {
            updateFeedback("Please wait for current processing to finish")
            refreshMenuState()
            return
        }
        Task {
            do {
                switch try await snapshotProcessingCoordinator.retrySelectionForCurrentContext() {
                case .noContext:
                    await MainActor.run {
                        self.updateFeedback("No context selected")
                        self.refreshMenuState()
                    }
                case .noFailedSnapshots:
                    await MainActor.run {
                        self.updateFeedback(SnapshotProcessingCoordinator.noFailedSnapshotsMessage)
                        self.refreshMenuState()
                    }
                case .snapshotIds(let snapshotIds):
                    await MainActor.run {
                        self.updateFeedback(SnapshotProcessingCoordinator.retryingMessage(for: snapshotIds.count))
                    }
                    let summary = await self.snapshotProcessingCoordinator.retrySnapshots(snapshotIds)
                    await MainActor.run {
                        self.updateFeedback(SnapshotProcessingCoordinator.retrySummaryMessage(summary))
                        self.refreshMenuState()
                    }
                }
            } catch {
                reportUnexpectedNonFatal(error, context: "retry_failed_snapshots_preflight")
                AppLogger.error("retryFailedSnapshots preflight failed: \(error.localizedDescription)")
                await MainActor.run {
                    self.updateFeedback("Retry failed")
                    self.refreshMenuState()
                }
            }
        }
    }

    @objc private func startNewContext() {
        AppLogger.debug("startNewContext tapped")
        eventTracker.track(.newContextRequested)
        guard hasSnapshotsInCurrentContext() || isCaptureInProgress else {
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
        guard !isAnyProcessing else {
            updateFeedback("Please wait for current processing to finish")
            refreshMenuState()
            return
        }
        guard hasSnapshotsInCurrentContext() else {
            updateFeedback("Nothing to copy yet")
            refreshMenuState()
            return
        }
        if hasFailedSnapshotsInCurrentContext() {
            updateFeedback("Resolve failed snapshots before copying")
            eventTracker.track(
                .copyContextFailed,
                parameters: [
                    "mode": analyticsExportModeName(.dense),
                    "source": source,
                    "error": "failed_snapshot_in_current_context"
                ]
            )
            presentFailedSnapshotsAlert()
            workspaceWindowController().show(section: .contextLibrary, sender: self)
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
            attemptPasteCurrentClipboard()
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

    private func attemptPasteCurrentClipboard() {
        guard permissionService.hasAccessibilityPermission() else {
            AppLogger.debug("attemptPasteCurrentClipboard skipped: missing accessibility permission")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let keyCode: CGKeyCode = 9
            let source = CGEventSource(stateID: .combinedSessionState)
            guard
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            else {
                AppLogger.error("attemptPasteCurrentClipboard failed: unable to create keyboard events")
                return
            }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            AppLogger.debug("attemptPasteCurrentClipboard posted command+v")
        }
    }

    @objc private func openSettings() {
        presentSettings(source: "menu")
    }

    @objc private func checkForUpdates() {
        UpdateChecker.shared.checkForUpdates()
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
            onRetryFailedSnapshot: { [weak self] snapshotId in
                guard let self else {
                    throw CancellationError()
                }
                return try await self.snapshotProcessingCoordinator.retrySnapshot(snapshotId)
            },
            onRetryFailedSnapshots: { [weak self] snapshotIds in
                guard let self else {
                    return SnapshotProcessingCoordinator.RetryBatchResult(succeeded: 0, failed: snapshotIds.count)
                }
                return await self.snapshotProcessingCoordinator.retrySnapshots(snapshotIds)
            },
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

    private func contextLabel(currentContext: Context?, hasSnapshotInCurrent: Bool) -> String {
        guard let currentContext else {
            return "New Context"
        }
        return hasSnapshotInCurrent ? currentContext.title : "Empty Context"
    }

    private var isCaptureInProgress: Bool {
        snapshotProcessingCoordinator.isCaptureInProgress
    }

    private var isAnyProcessing: Bool {
        snapshotProcessingCoordinator.isAnyProcessing
    }

    private func statusItemTitle() -> String {
        isAnyProcessing ? "Ctx..." : "Ctx"
    }

    private func processingStatusText() -> String? {
        if isCaptureInProgress {
            guard snapshotProcessingCoordinator.queuedCaptureCount > 0 else {
                return "Processing new snapshot..."
            }
            return "Processing new snapshot... (\(snapshotProcessingCoordinator.queuedCaptureCount) queued)"
        }
        guard snapshotProcessingCoordinator.activeRetryCount > 0 else {
            return nil
        }
        return "Processing new snapshot..."
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

    private func hasFailedSnapshotsInCurrentContext() -> Bool {
        (try? sessionManager.hasFailedSnapshotsInCurrentContext()) ?? false
    }

    private func updateActionHeadlines(contextLabel: String, lastSnapshot: Snapshot?) {
        let snapshotPreview = snapshotPreviewText(snapshot: lastSnapshot)
        let snapshotLabel = isAnyProcessing ? "Processing..." : snapshotPreview
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

    private func presentFailedSnapshotsAlert() {
        let alert = NSAlert()
        alert.messageText = "Failed Snapshots Found"
        alert.informativeText = "Current context contains failed snapshots. Retry or delete them in Context Library before copying."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Context Library")
        _ = alert.runModal()
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
        let requiresCredentials = developmentConfig.requiresCredentials(for: provider)
        let model = state.selectedModel ?? ""
        guard !requiresCredentials || !model.isEmpty else {
            AppLogger.debug("configuredModelConfig unavailable: model missing for provider=\(provider.rawValue)")
            return nil
        }
        let apiKey = try keychain.get("api.\(provider.rawValue)") ?? ""
        guard !requiresCredentials || !apiKey.isEmpty else {
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
        case .captureTargetIsContextBrief:
            return "self_frontmost"
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

extension MenuBarAppController: SnapshotProcessingCoordinatorDelegate {
    @MainActor
    func snapshotProcessingCoordinatorDidChangeProcessingState(_ coordinator: SnapshotProcessingCoordinator) {
        refreshMenuState()
    }

    @MainActor
    func snapshotProcessingCoordinator(
        _ coordinator: SnapshotProcessingCoordinator,
        didQueueCaptureFrom source: String,
        queuedCount: Int
    ) {
        updateFeedback(queuedCount == 1 ? "Snapshot queued for processing" : "\(queuedCount) snapshots queued for processing")
        AppLogger.info(
            "Capture queued source=\(source) queuedCount=\(queuedCount)"
        )
    }

    @MainActor
    func snapshotProcessingCoordinator(
        _ coordinator: SnapshotProcessingCoordinator,
        didStartCaptureFrom source: String
    ) {
        AppLogger.info(
            "Capture processing started source=\(source)"
        )
        eventTracker.track(.captureStarted, parameters: ["source": source])
    }

    @MainActor
    func snapshotProcessingCoordinator(
        _ coordinator: SnapshotProcessingCoordinator,
        didFinishCaptureFrom source: String,
        result: CaptureWorkflowResult
    ) {
        if result.snapshot.status == .failed {
            eventTracker.track(
                .captureFailed,
                parameters: [
                    "stage": "densification",
                    "error": result.snapshot.failureMessage ?? "densification_failed"
                ]
            )
            updateFeedback("Snapshot failed. Open Context Library to retry or delete.")
            AppLogger.error(
                "Capture densification failed source=\(source) snapshotId=\(result.snapshot.id.uuidString) reason=\(result.snapshot.failureMessage ?? "-")"
            )
            return
        }
        AppLogger.debug("captureContext success source=\(source) snapshotId=\(result.snapshot.id.uuidString) contextId=\(result.context.id.uuidString)")
        eventTracker.track(.captureSucceeded, parameters: ["sequence": result.snapshot.sequence])
        updateFeedback("Snapshot added to \(result.context.title)")
        Task {
            await applyGeneratedNames(result)
            await MainActor.run {
                self.refreshMenuState()
            }
        }
        AppLogger.info("Capture complete source=\(source) snapshot=\(result.snapshot.id.uuidString)")
    }

    @MainActor
    func snapshotProcessingCoordinator(
        _ coordinator: SnapshotProcessingCoordinator,
        didFailCaptureFrom source: String,
        stage: SnapshotProcessingCoordinator.CaptureFailureStage,
        error: Error
    ) {
        switch stage {
        case .capture:
            if let appError = error as? AppError {
                if case .captureTargetIsContextBrief = appError {
                    eventTracker.track(.captureBlocked, parameters: ["reason": "self_frontmost", "source": source])
                    AppLogger.debug("Capture skipped because Context Brief is frontmost")
                    return
                }
            }
            reportUnexpectedNonFatal(error, context: "capture_snapshot")
            if let appError = error as? AppError {
                updateFeedback("Snapshot failed: \(appError.localizedDescription)")
            } else {
                updateFeedback("Snapshot failed: \(error.localizedDescription)")
            }
            eventTracker.track(
                .captureFailed,
                parameters: [
                    "stage": "capture",
                    "error": analyticsErrorCode(error)
                ]
            )
            AppLogger.error("Capture snapshot failed source=\(source) error=\(error.localizedDescription)")
        case .workflow:
            reportUnexpectedNonFatal(error, context: "capture_workflow")
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
            AppLogger.error("Capture failed source=\(source) error=\(error.localizedDescription)")
        }
    }
}
