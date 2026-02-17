import AppKit
import ContextGenerator

final class ContextLibraryController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    private let repository: ContextRepositorying
    private let sessionManager: ContextSessionManager
    private let exportService: ContextExportService
    private let onSelectionChange: (String) -> Void
    private let retryFailedSnapshot: (UUID) async throws -> Snapshot

    private var contexts: [Context] = []
    private var snapshotsByContextId: [UUID: [Snapshot]] = [:]
    private var currentContextId: UUID?
    private var retryingSnapshotId: UUID?
    private var retryingFailedCurrentContextSnapshots = false
    private var didApplyInitialExpansionState = false

    private let outlineView = NSOutlineView()
    private let outlineScrollView = NSScrollView()
    private let detailTextView = NSTextView()
    private let detailScrollView = NSScrollView()
    private let contextMenu = NSMenu()
    private let snapshotMenu = NSMenu()

    init(
        repository: ContextRepositorying,
        sessionManager: ContextSessionManager,
        onSelectionChange: @escaping (String) -> Void,
        retryFailedSnapshot: @escaping (UUID) async throws -> Snapshot
    ) {
        self.repository = repository
        self.sessionManager = sessionManager
        exportService = ContextExportService(repository: repository)
        self.onSelectionChange = onSelectionChange
        self.retryFailedSnapshot = retryFailedSnapshot
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
        refreshData()
    }

    func refreshData() {
        let expandedContextIds = Set(
            contexts
                .filter { outlineView.isItemExpanded($0) }
                .map(\.id)
        )
        let selectedRow = outlineView.selectedRow
        let selectedItem = selectedRow >= 0
            ? outlineView.item(atRow: selectedRow)
            : nil
        let selectedContextId = (selectedItem as? Context)?.id
        let selectedSnapshotId = (selectedItem as? Snapshot)?.id
        do {
            contexts = try repository.listContexts()
            currentContextId = try sessionManager.currentContextIfExists()?.id
            snapshotsByContextId = Dictionary(
                uniqueKeysWithValues: try contexts.map { context in
                    (context.id, try repository.snapshots(in: context.id))
                }
            )
            guard isViewLoaded else {
                return
            }
            outlineView.reloadData()
            applyExpansionState(previouslyExpandedContextIds: expandedContextIds)
            if restoreSelection(
                selectedContextId: selectedContextId,
                selectedSnapshotId: selectedSnapshotId
            ) {
                showSelectionDetails()
            } else {
                detailTextView.string = contexts.isEmpty
                    ? "No contexts yet."
                    : "Select a context or snapshot."
            }
        } catch {
            onSelectionChange("Failed loading context library: \(error.localizedDescription)")
        }
    }

    private func setupUI() {
        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false

        let leftPane = NSView()
        let rightPane = NSView()
        leftPane.translatesAutoresizingMaskIntoConstraints = false
        rightPane.translatesAutoresizingMaskIntoConstraints = false
        splitView.addSubview(leftPane)
        splitView.addSubview(rightPane)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("libraryColumn"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.menu = contextMenu

        outlineScrollView.documentView = outlineView
        outlineScrollView.hasVerticalScroller = true
        outlineScrollView.translatesAutoresizingMaskIntoConstraints = false

        detailTextView.isEditable = false
        detailTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        detailTextView.isVerticallyResizable = true
        detailTextView.isHorizontallyResizable = false
        detailTextView.autoresizingMask = [.width]
        detailTextView.textContainerInset = NSSize(width: 12, height: 12)
        detailTextView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        detailTextView.textContainer?.widthTracksTextView = true
        detailScrollView.documentView = detailTextView
        detailScrollView.hasVerticalScroller = true
        detailScrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(splitView)
        leftPane.addSubview(outlineScrollView)
        rightPane.addSubview(detailScrollView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            leftPane.widthAnchor.constraint(equalToConstant: 360),

            outlineScrollView.topAnchor.constraint(equalTo: leftPane.topAnchor),
            outlineScrollView.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            outlineScrollView.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            outlineScrollView.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor),

            detailScrollView.topAnchor.constraint(equalTo: rightPane.topAnchor),
            detailScrollView.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            detailScrollView.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            detailScrollView.bottomAnchor.constraint(equalTo: rightPane.bottomAnchor)
        ])

        contextMenu.delegate = self
        contextMenu.autoenablesItems = false
        snapshotMenu.delegate = self
        snapshotMenu.autoenablesItems = false
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item else {
            return contexts.count
        }
        guard let context = item as? Context else {
            return 0
        }
        return snapshotsByContextId[context.id]?.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is Context
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item else {
            return contexts[index]
        }
        let context = item as! Context
        return snapshotsByContextId[context.id]?[index] as Any
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let context = item as? Context {
            return contextCellView(context: context)
        }
        if let snapshot = item as? Snapshot {
            return snapshotCellView(snapshot: snapshot)
        }
        return nil
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        showSelectionDetails()
    }

    private func contextCellView(context: Context) -> NSView {
        let container = NSTableCellView()
        let rowView = NSStackView()
        rowView.orientation = .horizontal
        rowView.alignment = .centerY
        rowView.spacing = 6
        rowView.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: context.title)
        title.lineBreakMode = .byTruncatingTail
        title.font = context.id == currentContextId
            ? NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            : NSFont.systemFont(ofSize: NSFont.systemFontSize)
        rowView.addArrangedSubview(title)
        rowView.addArrangedSubview(makeBadgeLabel(text: "\(context.snapshotCount)"))
        if context.id == currentContextId {
            rowView.addArrangedSubview(makeBadgeLabel(text: "Current", emphasis: true))
        }
        container.addSubview(rowView)
        NSLayoutConstraint.activate([
            rowView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            rowView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -6),
            rowView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func snapshotCellView(snapshot: Snapshot) -> NSView {
        let container = NSTableCellView()
        let rowView = NSStackView()
        rowView.orientation = .horizontal
        rowView.alignment = .centerY
        rowView.spacing = 6
        rowView.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "\(snapshot.sequence). \(snapshot.title)")
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rowView.addArrangedSubview(title)

        if snapshot.status == .failed {
            rowView.addArrangedSubview(
                makeBadgeLabel(
                    text: "Failed",
                    textColor: NSColor.systemRed,
                    backgroundColor: NSColor.systemRed.withAlphaComponent(0.18)
                )
            )
        }

        container.addSubview(rowView)
        NSLayoutConstraint.activate([
            rowView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            rowView.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -6),
            rowView.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func showSelectionDetails() {
        guard let selectedItem = outlineView.item(atRow: outlineView.selectedRow) else {
            detailTextView.string = "Select a context or snapshot."
            return
        }
        if let context = selectedItem as? Context {
            detailTextView.string = [
                context.id == currentContextId ? "Current Context" : "Context",
                context.title,
                "",
                "Snapshots: \(context.snapshotCount)"
            ].joined(separator: "\n")
            return
        }
        guard let snapshot = selectedItem as? Snapshot else {
            return
        }
        var details = [
            "Snapshot \(snapshot.sequence): \(snapshot.title)",
            "App: \(snapshot.appName)",
            "Window: \(snapshot.windowTitle)",
            "Status: \(snapshot.status == .failed ? "Failed" : "Ready")",
            "Retries: \(snapshot.retryCount)"
        ]
        if let lastAttemptAt = snapshot.lastAttemptAt {
            details.append("Last Attempt: \(lastAttemptAt.formatted())")
        }
        if snapshot.status == .failed, let failureMessage = snapshot.failureMessage, !failureMessage.isEmpty {
            details.append("")
            details.append("Failure")
            details.append(failureMessage)
        }
        details.append(contentsOf: [
            "",
            "Dense Content",
            snapshot.denseContent,
            "",
            "Raw Content",
            snapshot.rawContent
        ])
        detailTextView.string = details.joined(separator: "\n")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let clickedRow = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard clickedRow >= 0, let item = outlineView.item(atRow: clickedRow) else {
            return
        }
        outlineView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        if let context = item as? Context {
            populateContextMenu(context: context)
            return
        }
        if let snapshot = item as? Snapshot {
            populateSnapshotMenu(snapshot: snapshot)
        }
    }

    private func populateContextMenu(context: Context) {
        contextMenu.removeAllItems()
        if context.id != currentContextId {
            contextMenu.addItem(withTitle: "Set As Current", action: #selector(setCurrentContext), keyEquivalent: "")
        } else {
            let failedCount = failedSnapshotCount(in: context.id)
            if failedCount > 0 {
                let title = failedCount == 1
                    ? "Retry Failed Snapshot"
                    : "Retry Failed Snapshots (\(failedCount))"
                let retryItem = contextMenu.addItem(withTitle: title, action: #selector(retryFailedSnapshotsInSelectedContext), keyEquivalent: "")
                retryItem.isEnabled = !retryingFailedCurrentContextSnapshots
            }
        }
        contextMenu.addItem(withTitle: "Copy Context", action: #selector(copySelectedContext), keyEquivalent: "")
        contextMenu.addItem(withTitle: "Rename", action: #selector(renameSelectedContext), keyEquivalent: "")
        contextMenu.addItem(withTitle: "Delete", action: #selector(deleteSelectedContext), keyEquivalent: "")
        outlineView.menu = contextMenu
    }

    private func populateSnapshotMenu(snapshot: Snapshot) {
        snapshotMenu.removeAllItems()
        if snapshot.status == .failed {
            let retryItem = snapshotMenu.addItem(withTitle: "Retry", action: #selector(retrySelectedSnapshot), keyEquivalent: "")
            retryItem.isEnabled = retryingSnapshotId != snapshot.id
        }
        if snapshot.contextId != currentContextId {
            snapshotMenu.addItem(withTitle: "Move To Current Context", action: #selector(moveSelectedSnapshotToCurrentContext), keyEquivalent: "")
        } else {
            snapshotMenu.addItem(withTitle: "Move to New Context", action: #selector(moveSelectedSnapshotToNewContext), keyEquivalent: "")
        }
        snapshotMenu.addItem(withTitle: "Delete", action: #selector(deleteSelectedSnapshot), keyEquivalent: "")
        outlineView.menu = snapshotMenu
    }

    func createNewContextFromSidebar() {
        createNewContext()
    }

    @objc private func setCurrentContext() {
        guard let context = selectedContext() else {
            return
        }
        do {
            try sessionManager.setCurrentContext(context.id)
            onSelectionChange("Current context: \(context.title)")
            refreshData()
        } catch {
            onSelectionChange("Set context failed: \(error.localizedDescription)")
        }
    }

    @objc private func renameSelectedContext() {
        guard let context = selectedContext() else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "Rename Context"
        alert.informativeText = "Enter a new context name."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = context.title
        alert.accessoryView = input
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        let newTitle = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty else {
            return
        }

        do {
            _ = try sessionManager.renameContext(context.id, title: newTitle)
            onSelectionChange("Renamed context")
            refreshData()
        } catch {
            onSelectionChange("Rename failed: \(error.localizedDescription)")
        }
    }

    @objc private func deleteSelectedContext() {
        guard let context = selectedContext() else {
            return
        }
        do {
            let moved = try sessionManager.deleteContextToTrash(context.id)
            onSelectionChange("Deleted context. Moved \(moved) snapshots to trash")
            refreshData()
        } catch {
            onSelectionChange("Delete context failed: \(error.localizedDescription)")
        }
    }

    @objc private func moveSelectedSnapshotToCurrentContext() {
        guard let snapshot = selectedSnapshot() else {
            return
        }
        do {
            let moved = try sessionManager.moveSnapshotToCurrentContext(snapshot.id)
            onSelectionChange("Moved \(moved.title) to current context")
            refreshData()
        } catch {
            onSelectionChange("Move snapshot failed: \(error.localizedDescription)")
        }
    }

    @objc private func moveSelectedSnapshotToNewContext() {
        guard let snapshot = selectedSnapshot() else {
            return
        }
        do {
            let moved = try sessionManager.moveSnapshotToNewContext(snapshot.id, title: "New Context")
            onSelectionChange("Moved \(moved.snapshot.title) to new context")
            refreshData()
        } catch {
            onSelectionChange("Move snapshot failed: \(error.localizedDescription)")
        }
    }

    @objc private func deleteSelectedSnapshot() {
        guard let snapshot = selectedSnapshot() else {
            return
        }
        do {
            let moved = try sessionManager.deleteSnapshotToTrash(snapshot.id)
            onSelectionChange("Moved \(moved.title) to trash")
            refreshData()
        } catch {
            onSelectionChange("Delete snapshot failed: \(error.localizedDescription)")
        }
    }

    @objc private func retrySelectedSnapshot() {
        guard let snapshot = selectedSnapshot(), snapshot.status == .failed else {
            return
        }
        guard retryingSnapshotId == nil else {
            return
        }
        let originalCurrentContextId: UUID?
        do {
            originalCurrentContextId = try sessionManager.currentContextIfExists()?.id
        } catch {
            originalCurrentContextId = nil
        }
        retryingSnapshotId = snapshot.id
        onSelectionChange("Retrying \(snapshot.title)...")
        Task {
            do {
                let retried = try await retryFailedSnapshot(snapshot.id)
                await MainActor.run {
                    self.restoreCurrentContextIfNeeded(originalCurrentContextId)
                    self.retryingSnapshotId = nil
                    self.onSelectionChange("Retry succeeded for \(retried.title)")
                    self.refreshData()
                }
            } catch {
                await MainActor.run {
                    self.restoreCurrentContextIfNeeded(originalCurrentContextId)
                    self.retryingSnapshotId = nil
                    self.onSelectionChange("Retry failed: \(error.localizedDescription)")
                    self.refreshData()
                }
            }
        }
    }

    @objc private func retryFailedSnapshotsInSelectedContext() {
        guard let context = selectedContext(), context.id == currentContextId else {
            return
        }
        guard !retryingFailedCurrentContextSnapshots else {
            return
        }
        let originalCurrentContextId: UUID?
        do {
            originalCurrentContextId = try sessionManager.currentContextIfExists()?.id
        } catch {
            originalCurrentContextId = nil
        }
        let failedSnapshots = snapshotsByContextId[context.id]?.filter { $0.status == .failed } ?? []
        guard !failedSnapshots.isEmpty else {
            onSelectionChange("No failed snapshots to retry")
            return
        }

        retryingFailedCurrentContextSnapshots = true
        onSelectionChange(
            failedSnapshots.count == 1
                ? "Retrying 1 failed snapshot..."
                : "Retrying \(failedSnapshots.count) failed snapshots..."
        )
        Task {
            var succeededCount = 0
            var failedCount = 0
            for snapshot in failedSnapshots {
                do {
                    _ = try await retryFailedSnapshot(snapshot.id)
                    succeededCount += 1
                } catch {
                    failedCount += 1
                }
            }
            await MainActor.run {
                self.restoreCurrentContextIfNeeded(originalCurrentContextId)
                self.retryingFailedCurrentContextSnapshots = false
                if failedCount == 0 {
                    self.onSelectionChange(
                        succeededCount == 1
                            ? "Retried 1 failed snapshot"
                            : "Retried \(succeededCount) failed snapshots"
                    )
                } else {
                    self.onSelectionChange("Retried \(succeededCount), failed \(failedCount)")
                }
                self.refreshData()
            }
        }
    }

    @objc private func copySelectedContext() {
        guard let context = selectedContext() else {
            return
        }
        if failedSnapshotCount(in: context.id) > 0 {
            onSelectionChange("Resolve failed snapshots before copying")
            presentFailedSnapshotsAlert()
            return
        }
        do {
            let text = try exportService.exportText(contextId: context.id, mode: .dense)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            onSelectionChange("Copied dense context")
        } catch {
            onSelectionChange("Copy failed: \(error.localizedDescription)")
        }
    }

    @objc private func createNewContext() {
        do {
            _ = try sessionManager.createNewContext(title: "New Context")
            onSelectionChange("Started a new context")
            refreshData()
        } catch {
            onSelectionChange("New context failed: \(error.localizedDescription)")
        }
    }

    private func selectedContext() -> Context? {
        if let context = outlineView.item(atRow: outlineView.selectedRow) as? Context {
            return context
        }
        if let snapshot = outlineView.item(atRow: outlineView.selectedRow) as? Snapshot {
            return contexts.first(where: { $0.id == snapshot.contextId })
        }
        return nil
    }

    private func selectedSnapshot() -> Snapshot? {
        outlineView.item(atRow: outlineView.selectedRow) as? Snapshot
    }

    private func failedSnapshotCount(in contextId: UUID) -> Int {
        snapshotsByContextId[contextId]?.filter { $0.status == .failed }.count ?? 0
    }

    private func restoreCurrentContextIfNeeded(_ originalCurrentContextId: UUID?) {
        guard let originalCurrentContextId else {
            return
        }
        let activeContextId: UUID?
        do {
            activeContextId = try sessionManager.currentContextIfExists()?.id
        } catch {
            return
        }
        guard let activeContextId, activeContextId != originalCurrentContextId else {
            return
        }
        do {
            try sessionManager.setCurrentContext(originalCurrentContextId)
        } catch {
            onSelectionChange("Set context failed: \(error.localizedDescription)")
        }
    }

    private func presentFailedSnapshotsAlert() {
        let alert = NSAlert()
        alert.messageText = "Failed Snapshots Found"
        alert.informativeText = "Current context contains failed snapshots. Retry or delete them in Context Library before copying."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Context Library")
        _ = alert.runModal()
    }

    private func applyInitialExpansionState() {
        contexts.forEach { outlineView.collapseItem($0) }
        if let currentContext = contexts.first(where: { $0.id == currentContextId }) {
            outlineView.expandItem(currentContext)
        }
    }

    private func applyExpansionState(previouslyExpandedContextIds: Set<UUID>) {
        if !didApplyInitialExpansionState {
            applyInitialExpansionState()
            didApplyInitialExpansionState = true
            return
        }

        contexts.forEach { context in
            if previouslyExpandedContextIds.contains(context.id) {
                outlineView.expandItem(context)
            } else {
                outlineView.collapseItem(context)
            }
        }
    }

    private func restoreSelection(selectedContextId: UUID?, selectedSnapshotId: UUID?) -> Bool {
        if let selectedSnapshotId {
            for context in contexts {
                guard
                    let snapshots = snapshotsByContextId[context.id],
                    let snapshot = snapshots.first(where: { $0.id == selectedSnapshotId })
                else {
                    continue
                }
                let row = outlineView.row(forItem: snapshot)
                if row >= 0 {
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    return true
                }
            }
        }

        if
            let selectedContextId,
            let context = contexts.first(where: { $0.id == selectedContextId })
        {
            let row = outlineView.row(forItem: context)
            if row >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                return true
            }
        }

        guard let first = contexts.first else {
            return false
        }

        let row = outlineView.row(forItem: first)
        guard row >= 0 else {
            return false
        }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return true
    }

    private func makeBadgeLabel(
        text: String,
        emphasis: Bool = false,
        textColor: NSColor? = nil,
        backgroundColor: NSColor? = nil
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = textColor ?? (emphasis ? NSColor.white : NSColor.secondaryLabelColor)
        label.wantsLayer = true
        label.layer?.cornerRadius = 8
        label.layer?.masksToBounds = true
        label.layer?.backgroundColor = (
            backgroundColor
            ?? (emphasis ? NSColor.systemBlue : NSColor.quaternaryLabelColor)
        ).cgColor
        label.alignment = .center
        label.cell?.usesSingleLineMode = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.heightAnchor.constraint(equalToConstant: 16).isActive = true
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: text.count > 2 ? 28 : 20).isActive = true
        return label
    }
}
