import AppKit
import ContextGenerator

final class MenuBarAppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
    private var separatorAfterSettings: NSMenuItem?
    private var isCaptureInProgress = false
    private var deferredUndoForInFlightCapture = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLogger.debug("App launch finished. debugLoggingEnabled=\(AppLogger.debugLoggingEnabled)")
        setupMainMenu()
        setupStatusItem()
        ensureOnboarding()
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
        addSnapshotMenuItem = addMenuItem("Add Snapshot to Context", action: #selector(captureContext), key: "c", menu: menu)
        copyDenseMenuItem = addMenuItem("Copy Current Context", action: #selector(copyDenseCurrentContext), key: "d", menu: menu)
        separatorAfterPrimary = .separator()
        if let separatorAfterPrimary {
            menu.addItem(separatorAfterPrimary)
        }

        snapshotActionsHeadlineMenuItem = NSMenuItem(title: "Snapshot", action: nil, keyEquivalent: "")
        snapshotActionsHeadlineMenuItem?.isEnabled = false
        if let snapshotActionsHeadlineMenuItem {
            menu.addItem(snapshotActionsHeadlineMenuItem)
        }
        undoSnapshotMenuItem = addMenuItem("Delete Last Snapshot", action: #selector(undoLastCapture), key: "", menu: menu)
        promoteSnapshotMenuItem = addMenuItem("Move Last Snapshot to New Context", action: #selector(promoteLastCapture), key: "", menu: menu)
        newContextMenuItem = addMenuItem("Start New Context", action: #selector(startNewContext), key: "n", menu: menu)
        separatorAfterActions = .separator()
        if let separatorAfterActions {
            menu.addItem(separatorAfterActions)
        }
        _ = addMenuItem("Open Context Library", action: #selector(openContextLibrary), key: "", menu: menu)
        separatorAfterLibrary = .separator()
        if let separatorAfterLibrary {
            menu.addItem(separatorAfterLibrary)
        }
        _ = addMenuItem("Settings", action: #selector(openSettings), key: "", menu: menu)
        separatorAfterSettings = .separator()
        if let separatorAfterSettings {
            menu.addItem(separatorAfterSettings)
        }
        _ = addMenuItem("Quit", action: #selector(quit), key: "", menu: menu)

        statusItem.menu = menu
        self.statusItem = statusItem
        AppLogger.debug("Status menu configured with primary actions and sections")
        refreshMenuState()
    }

    private func addMenuItem(_ title: String, action: Selector, key: String, menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    private func ensureOnboarding() {
        do {
            let state = try appStateService.state()
            AppLogger.debug(
                "ensureOnboarding state onboardingCompleted=\(state.onboardingCompleted) provider=\(String(describing: state.selectedProvider?.rawValue)) model=\(String(describing: state.selectedModel))"
            )
            if state.onboardingCompleted {
                refreshMenuState()
                return
            }
        } catch {
            AppLogger.error("ensureOnboarding failed: \(error.localizedDescription)")
        }

        openSettings()
    }

    func menuWillOpen(_ menu: NSMenu) {
        AppLogger.debug("Menu will open")
        refreshMenuState()
    }

    private func refreshMenuState() {
        do {
            let state = try appStateService.state()
            let hasPermissions = permissionService.hasAccessibilityPermission() && permissionService.hasScreenRecordingPermission()
            let setupReady = state.onboardingCompleted && hasPermissions
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
                setupStatusMenuItem?.title = state.onboardingCompleted
                    ? "Permissions required: Accessibility + Screen Recording"
                    : "Setup required: provider, model and API key"
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
                "refreshMenuState onboardingCompleted=\(state.onboardingCompleted) hasPermissions=\(hasPermissions) setupReady=\(setupReady) currentContextId=\(currentContext?.id.uuidString ?? "-") currentContextTitle=\(currentContext?.title ?? "-") hasSnapshotInCurrent=\(hasSnapshotInCurrent) captureInProgress=\(isCaptureInProgress) deferredUndo=\(deferredUndoForInFlightCapture)"
            )
            applySetupVisibility(setupReady: setupReady)
        } catch {
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
        setHidden(newContextMenuItem, hidden: hideActions)
        setHidden(separatorAfterActions, hidden: hideActions)
    }

    private func setHidden(_ item: NSMenuItem?, hidden: Bool) {
        item?.isHidden = hidden
    }

    @objc private func captureContext() {
        AppLogger.debug("captureContext tapped")
        if isCaptureInProgress {
            updateFeedback("Snapshot already processing")
            return
        }
        do {
            let state = try appStateService.state()
            guard state.onboardingCompleted else {
                AppLogger.debug("captureContext blocked: onboarding not completed")
                openSettings()
                return
            }
            guard permissionService.hasAccessibilityPermission(), permissionService.hasScreenRecordingPermission() else {
                AppLogger.debug("captureContext blocked: missing permissions")
                openSettings()
                return
            }
        } catch {
            AppLogger.error("captureContext state check failed: \(error.localizedDescription)")
            return
        }

        AppLogger.info("Capture requested")
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
                updateFeedback("Snapshot added to \(result.context.title)")
                await applyGeneratedNames(result)
                await MainActor.run { [weak self] in
                    self?.isCaptureInProgress = false
                    self?.refreshMenuState()
                }
                AppLogger.info("Capture complete snapshot=\(result.snapshot.id.uuidString)")
            } catch {
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
                AppLogger.error("Capture failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func undoLastCapture() {
        AppLogger.debug("undoLastCapture tapped")
        if isCaptureInProgress {
            deferredUndoForInFlightCapture = true
            updateFeedback("Will remove processing snapshot when ready")
            refreshMenuState()
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
            updateFeedback("Moved \(removed.title) to trash")
            refreshMenuState()
        } catch {
            AppLogger.error("undoLastCapture failed: \(error.localizedDescription)")
            updateFeedback("Undo failed")
        }
    }

    @objc private func promoteLastCapture() {
        AppLogger.debug("promoteLastCapture tapped")
        guard hasSnapshotsInCurrentContext() else {
            updateFeedback("No snapshot to move")
            refreshMenuState()
            return
        }
        do {
            let context = try sessionManager.promoteLastCaptureToNewContext()
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
            AppLogger.error("promoteLastCapture failed: \(error.localizedDescription)")
            updateFeedback("Move failed")
        }
    }

    @objc private func startNewContext() {
        AppLogger.debug("startNewContext tapped")
        guard hasSnapshotsInCurrentContext() else {
            updateFeedback("Current context is already empty")
            refreshMenuState()
            return
        }
        do {
            let context = try sessionManager.createNewContext(title: "New Context")
            AppLogger.debug("startNewContext success contextId=\(context.id.uuidString)")
            updateFeedback("Started a new context")
            refreshMenuState()
        } catch {
            AppLogger.error("startNewContext failed: \(error.localizedDescription)")
            updateFeedback("New context failed")
        }
    }

    @objc private func openContextLibrary() {
        workspaceWindowController().show(section: .contextLibrary, sender: self)
    }

    @objc private func copyDenseCurrentContext() {
        AppLogger.debug("copyDenseCurrentContext tapped")
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
            AppLogger.debug("copyCurrentContext success contextId=\(context.id.uuidString) mode=dense chars=\(text.count)")
            updateFeedback("Copied dense context")
        } catch {
            AppLogger.error("copyCurrentContext failed: \(error.localizedDescription)")
            updateFeedback("Copy failed")
            AppLogger.error("Copy failed: \(error.localizedDescription)")
        }
    }

    @objc private func openSettings() {
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
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        )
    }

    private func configuredModelConfig() throws -> (ProviderName, String, String)? {
        let state = try appStateService.state()
        guard let provider = state.selectedProvider, let model = state.selectedModel else {
            AppLogger.debug("configuredModelConfig unavailable: provider/model missing")
            return nil
        }
        guard let apiKey = try keychain.get("api.\(provider.rawValue)") else {
            AppLogger.debug("configuredModelConfig unavailable: key missing for provider=\(provider.rawValue)")
            return nil
        }
        AppLogger.debug("configuredModelConfig available provider=\(provider.rawValue) model=\(model)")
        return (provider, model, apiKey)
    }

    private func applyGeneratedNames(_ result: CaptureWorkflowResult) async {
        guard let config = ((try? configuredModelConfig()) ?? nil) else {
            AppLogger.debug("applyGeneratedNames skipped: model config unavailable")
            return
        }

        let snapshotTitle = await namingService.suggestSnapshotTitle(
            capturedSnapshot: result.capturedSnapshot,
            denseContent: result.snapshot.denseContent,
            provider: config.0,
            model: config.1,
            apiKey: config.2,
            fallback: result.snapshot.title
        )

        do {
            let snapshot = try sessionManager.renameSnapshot(result.snapshot.id, title: snapshotTitle)
            AppLogger.debug("applyGeneratedNames snapshot title updated snapshotId=\(snapshot.id.uuidString) title=\(snapshot.title)")
        } catch {}

        await applyGeneratedContextName(contextId: result.context.id, fallback: result.context.title)
    }

    private func applyGeneratedContextName(contextId: UUID, fallback: String) async {
        guard let config = ((try? configuredModelConfig()) ?? nil) else {
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
            provider: config.0,
            model: config.1,
            apiKey: config.2,
            fallback: fallback
        )
        _ = try? sessionManager.renameContext(contextId, title: title)
        AppLogger.debug("applyGeneratedContextName updated contextId=\(contextId.uuidString) oldTitle=\(context.title) newTitle=\(title)")
    }
}
