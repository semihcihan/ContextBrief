import AppKit
import ContextGenerator

final class MenuBarAppController: NSObject, NSApplicationDelegate {
    private let repository = ContextRepository()
    private lazy var sessionManager = ContextSessionManager(repository: repository)
    private let captureService = ContextCaptureService()
    private let keychain = KeychainService()
    private lazy var appStateService = AppStateService(repository: repository, keychain: keychain)
    private lazy var densificationService = DensificationService()
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
    private var onboardingController: OnboardingWindowController?
    private var libraryController: ContextLibraryController?
    private var statusMenuItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        ensureOnboarding()
    }

    private func setupStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Ctx"

        let menu = NSMenu()
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        addMenuItem("Capture Context", action: #selector(captureContext), key: "c", menu: menu)
        addMenuItem("Undo Last Capture", action: #selector(undoLastCapture), key: "z", menu: menu)
        addMenuItem("Add Last Capture As New Context", action: #selector(promoteLastCapture), key: "n", menu: menu)
        addMenuItem("Open Context Library", action: #selector(openContextLibrary), key: "l", menu: menu)
        addMenuItem("Copy Current Context (Dense)", action: #selector(copyDenseCurrentContext), key: "d", menu: menu)
        addMenuItem("Copy Current Context (Raw)", action: #selector(copyRawCurrentContext), key: "r", menu: menu)
        addMenuItem("Settings", action: #selector(openSettings), key: "s", menu: menu)
        menu.addItem(.separator())
        addMenuItem("Quit", action: #selector(quit), key: "q", menu: menu)

        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func addMenuItem(_ title: String, action: Selector, key: String, menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func ensureOnboarding() {
        do {
            let state = try appStateService.state()
            if state.onboardingCompleted {
                updateStatus("Ready")
                _ = try sessionManager.currentContext()
                return
            }
        } catch {
            updateStatus("State load failed")
        }

        openSettings()
    }

    @objc private func captureContext() {
        do {
            let state = try appStateService.state()
            guard state.onboardingCompleted else {
                updateStatus("Complete setup first")
                openSettings()
                return
            }
            guard permissionService.hasAccessibilityPermission(), permissionService.hasScreenRecordingPermission() else {
                updateStatus("Missing permissions")
                openSettings()
                return
            }
        } catch {
            updateStatus("State check failed")
            return
        }

        updateStatus("Capturing...")
        AppLogger.info("Capture requested")
        Task {
            do {
                let result = try await workflow.runCapture()
                updateStatus("Captured in \(result.context.title) (\(result.context.pieceCount + 1) pieces)")
                AppLogger.info("Capture complete piece=\(result.piece.id.uuidString)")
            } catch {
                updateStatus("Capture failed: \(error.localizedDescription)")
                AppLogger.error("Capture failed: \(error.localizedDescription)")
            }
        }
    }

    @objc private func undoLastCapture() {
        do {
            let removed = try sessionManager.undoLastCaptureInCurrentContext()
            updateStatus("Removed piece \(removed.sequence)")
        } catch {
            updateStatus("Undo failed: \(error.localizedDescription)")
        }
    }

    @objc private func promoteLastCapture() {
        do {
            let context = try sessionManager.promoteLastCaptureToNewContext()
            updateStatus("Promoted to \(context.title)")
        } catch {
            updateStatus("Promote failed: \(error.localizedDescription)")
        }
    }

    @objc private func openContextLibrary() {
        if libraryController == nil {
            libraryController = ContextLibraryController(
                repository: repository,
                sessionManager: sessionManager,
                onSelectionChange: { [weak self] text in
                    self?.updateStatus(text)
                }
            )
        }
        libraryController?.showWindow(self)
    }

    @objc private func copyDenseCurrentContext() {
        copyCurrentContext(mode: .dense)
    }

    @objc private func copyRawCurrentContext() {
        copyCurrentContext(mode: .raw)
    }

    private func copyCurrentContext(mode: ExportMode) {
        do {
            let context = try sessionManager.currentContext()
            let text = try exportService.exportText(contextId: context.id, mode: mode)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            updateStatus("Copied \(mode == .dense ? "dense" : "raw") context")
        } catch {
            updateStatus("Copy failed: \(error.localizedDescription)")
            AppLogger.error("Copy failed: \(error.localizedDescription)")
        }
    }

    @objc private func openSettings() {
        onboardingController = OnboardingWindowController(
            permissionService: permissionService,
            appStateService: appStateService,
            onComplete: { [weak self] in
                self?.updateStatus("Setup complete")
            }
        )
        onboardingController?.showWindow(self)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func updateStatus(_ text: String) {
        DispatchQueue.main.async {
            self.statusMenuItem.title = text
        }
    }
}
