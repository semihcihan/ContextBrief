import AppKit
import ContextGenerator

final class TrashLibraryController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    private enum TrashItem {
        case context(TrashedContext)
        case snapshot(TrashedSnapshot)
    }

    private let sessionManager: ContextSessionManager
    private let onSelectionChange: (String) -> Void
    private var trashedSnapshots: [TrashedSnapshot] = []
    private var trashedContexts: [TrashedContext] = []
    private var items: [TrashItem] = []

    private let tableView = NSTableView()
    private let tableScrollView = NSScrollView()
    private let detailTextView = NSTextView()
    private let detailScrollView = NSScrollView()
    private let rowMenu = NSMenu()

    init(
        sessionManager: ContextSessionManager,
        onSelectionChange: @escaping (String) -> Void
    ) {
        self.sessionManager = sessionManager
        self.onSelectionChange = onSelectionChange
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
        do {
            trashedSnapshots = try sessionManager.trashedSnapshots()
            trashedContexts = try sessionManager.trashedContexts()
            let entries: [(deletedAt: Date, item: TrashItem)] =
                trashedContexts.map { (deletedAt: $0.deletedAt, item: .context($0)) }
                + trashedSnapshots.map { (deletedAt: $0.deletedAt, item: .snapshot($0)) }
            items = entries
                .sorted(by: { $0.deletedAt > $1.deletedAt })
                .map(\.item)
            tableView.reloadData()
            if items.isEmpty {
                detailTextView.string = "Trash is empty."
                return
            }
            let selected = max(0, min(tableView.selectedRow, items.count - 1))
            tableView.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
            showSelectedDetails()
        } catch {
            onSelectionChange("Failed loading trash: \(error.localizedDescription)")
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

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("trashColumn"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.dataSource = self
        tableView.delegate = self
        rowMenu.delegate = self
        rowMenu.autoenablesItems = false
        tableView.menu = rowMenu

        tableScrollView.documentView = tableView
        tableScrollView.hasVerticalScroller = true
        tableScrollView.translatesAutoresizingMaskIntoConstraints = false

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
        leftPane.addSubview(tableScrollView)
        rightPane.addSubview(detailScrollView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            leftPane.widthAnchor.constraint(equalToConstant: 380),

            tableScrollView.topAnchor.constraint(equalTo: leftPane.topAnchor),
            tableScrollView.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            tableScrollView.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            tableScrollView.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor),

            detailScrollView.topAnchor.constraint(equalTo: rightPane.topAnchor),
            detailScrollView.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            detailScrollView.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            detailScrollView.bottomAnchor.constraint(equalTo: rightPane.bottomAnchor)
        ])
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("trashRow")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let created = NSTableCellView()
            created.identifier = identifier
            let stack = NSStackView()
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 6
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.identifier = NSUserInterfaceItemIdentifier("stack")

            let badge = makeBadgeLabel(text: "")
            badge.identifier = NSUserInterfaceItemIdentifier("badge")
            let title = NSTextField(labelWithString: "")
            title.identifier = NSUserInterfaceItemIdentifier("title")
            title.lineBreakMode = .byTruncatingTail

            stack.addArrangedSubview(badge)
            stack.addArrangedSubview(title)
            created.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: created.leadingAnchor, constant: 6),
                stack.trailingAnchor.constraint(equalTo: created.trailingAnchor, constant: -6),
                stack.centerYAnchor.constraint(equalTo: created.centerYAnchor)
            ])
            return created
        }()

        let stack = cell.subviews.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("stack") }) as? NSStackView
        let badge = stack?.views.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("badge") }) as? NSTextField
        let title = stack?.views.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("title") }) as? NSTextField

        switch items[row] {
        case .context(let context):
            badge?.stringValue = "Context"
            title?.stringValue = context.context.title
        case .snapshot(let snapshot):
            badge?.stringValue = "Snapshot"
            title?.stringValue = "\(snapshot.snapshot.title) - \(snapshot.sourceContextTitle)"
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        showSelectedDetails()
    }

    private func showSelectedDetails() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < items.count else {
            detailTextView.string = items.isEmpty ? "Trash is empty." : "Select an item."
            return
        }
        switch items[selectedRow] {
        case .context(let context):
            detailTextView.string = [
                "Trashed Context: \(context.context.title)",
                "Snapshots: \(context.snapshots.count)",
                "",
                "Created: \(context.context.createdAt.formatted())",
                "Deleted: \(context.deletedAt.formatted())"
            ].joined(separator: "\n")
        case .snapshot(let item):
            let snapshot = item.snapshot
            detailTextView.string = [
                "Trashed Snapshot: \(snapshot.title)",
                "From Context: \(item.sourceContextTitle)",
                "App: \(snapshot.appName)",
                "Window: \(snapshot.windowTitle)",
                "",
                "Dense Content",
                snapshot.denseContent,
                "",
                "Raw Content",
                snapshot.rawContent
            ].joined(separator: "\n")
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rowMenu.removeAllItems()
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < items.count else {
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        switch items[row] {
        case .context:
            rowMenu.addItem(withTitle: "Restore Context", action: #selector(restoreSelectedContext), keyEquivalent: "")
            rowMenu.addItem(withTitle: "Delete Permanently", action: #selector(deleteSelectedContextPermanently), keyEquivalent: "")
        case .snapshot:
            rowMenu.addItem(withTitle: "Move To Current Context", action: #selector(restoreSelectedSnapshot), keyEquivalent: "")
            rowMenu.addItem(withTitle: "Delete Permanently", action: #selector(deleteSelectedSnapshotPermanently), keyEquivalent: "")
        }
    }

    @objc private func restoreSelectedSnapshot() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < items.count else {
            return
        }
        guard case .snapshot(let item) = items[selectedRow] else {
            return
        }
        do {
            let restored = try sessionManager.restoreTrashedSnapshotToCurrentContext(item.id)
            onSelectionChange("Moved \(restored.title) to current context")
            refreshData()
        } catch {
            onSelectionChange("Restore failed: \(error.localizedDescription)")
        }
    }

    @objc private func restoreSelectedContext() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < items.count else {
            return
        }
        guard case .context(let item) = items[selectedRow] else {
            return
        }
        do {
            let restored = try sessionManager.restoreTrashedContext(item.id)
            onSelectionChange("Restored context \(restored.title)")
            refreshData()
        } catch {
            onSelectionChange("Restore context failed: \(error.localizedDescription)")
        }
    }

    @objc private func deleteSelectedSnapshotPermanently() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < items.count else {
            return
        }
        guard case .snapshot(let item) = items[selectedRow] else {
            return
        }
        guard
            confirmPermanentDelete(
                title: "Delete Snapshot Permanently",
                message: "Permanently delete \"\(item.snapshot.title)\" from Trash? This cannot be undone."
            )
        else {
            return
        }
        do {
            try sessionManager.deleteTrashedSnapshotPermanently(item.id)
            onSelectionChange("Deleted snapshot permanently")
            refreshData()
        } catch {
            onSelectionChange("Permanent delete failed: \(error.localizedDescription)")
        }
    }

    @objc private func deleteSelectedContextPermanently() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < items.count else {
            return
        }
        guard case .context(let item) = items[selectedRow] else {
            return
        }
        guard
            confirmPermanentDelete(
                title: "Delete Context Permanently",
                message: "Permanently delete \"\(item.context.title)\" and its snapshots from Trash? This cannot be undone."
            )
        else {
            return
        }
        do {
            try sessionManager.deleteTrashedContextPermanently(item.id)
            onSelectionChange("Deleted context permanently")
            refreshData()
        } catch {
            onSelectionChange("Permanent delete failed: \(error.localizedDescription)")
        }
    }

    private func confirmPermanentDelete(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete Permanently")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func makeBadgeLabel(text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor.secondaryLabelColor
        label.wantsLayer = true
        label.layer?.cornerRadius = 8
        label.layer?.masksToBounds = true
        label.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        label.alignment = .center
        label.cell?.usesSingleLineMode = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.heightAnchor.constraint(equalToConstant: 16).isActive = true
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        return label
    }
}
