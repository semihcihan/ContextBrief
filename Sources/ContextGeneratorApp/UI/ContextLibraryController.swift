import AppKit
import ContextGenerator

final class ContextLibraryController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    private let repository: ContextRepositorying
    private let sessionManager: ContextSessionManager
    private let onSelectionChange: (String) -> Void

    private var contexts: [Context] = []
    private var snapshotsByContextId: [UUID: [Snapshot]] = [:]
    private var currentContextId: UUID?

    private let outlineView = NSOutlineView()
    private let outlineScrollView = NSScrollView()
    private let detailTextView = NSTextView()
    private let detailScrollView = NSScrollView()
    private let contextMenu = NSMenu()
    private let snapshotMenu = NSMenu()

    init(
        repository: ContextRepositorying,
        sessionManager: ContextSessionManager,
        onSelectionChange: @escaping (String) -> Void
    ) {
        self.repository = repository
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
            contexts = try repository.listContexts()
            currentContextId = try sessionManager.currentContextIfExists()?.id
            snapshotsByContextId = Dictionary(
                uniqueKeysWithValues: try contexts.map { context in
                    (context.id, try repository.snapshots(in: context.id))
                }
            )
            outlineView.reloadData()
            contexts.forEach { outlineView.expandItem($0) }
            if outlineView.selectedRow >= 0 {
                showSelectionDetails()
            } else if let first = contexts.first {
                let row = outlineView.row(forItem: first)
                if row >= 0 {
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    showSelectionDetails()
                } else {
                    detailTextView.string = "Select a context or snapshot."
                }
            } else {
                detailTextView.string = "No contexts yet."
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
            let identifier = NSUserInterfaceItemIdentifier("snapshotCell")
            let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
                let created = NSTableCellView()
                created.identifier = identifier
                let label = NSTextField(labelWithString: "")
                label.translatesAutoresizingMaskIntoConstraints = false
                created.textField = label
                created.addSubview(label)
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: created.leadingAnchor, constant: 6),
                    label.trailingAnchor.constraint(equalTo: created.trailingAnchor, constant: -6),
                    label.centerYAnchor.constraint(equalTo: created.centerYAnchor)
                ])
                return created
            }()
            cell.textField?.stringValue = "\(snapshot.sequence). \(snapshot.title)"
            return cell
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
        detailTextView.string = [
            "Snapshot \(snapshot.sequence): \(snapshot.title)",
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
        }
        contextMenu.addItem(withTitle: "Rename", action: #selector(renameSelectedContext), keyEquivalent: "")
        contextMenu.addItem(withTitle: "Delete", action: #selector(deleteSelectedContext), keyEquivalent: "")
        outlineView.menu = contextMenu
    }

    private func populateSnapshotMenu(snapshot: Snapshot) {
        snapshotMenu.removeAllItems()
        if snapshot.contextId != currentContextId {
            snapshotMenu.addItem(withTitle: "Move To Current Context", action: #selector(moveSelectedSnapshotToCurrentContext), keyEquivalent: "")
        }
        snapshotMenu.addItem(withTitle: "Delete", action: #selector(deleteSelectedSnapshot), keyEquivalent: "")
        outlineView.menu = snapshotMenu
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
            var renamed = context
            renamed.title = newTitle
            renamed.updatedAt = Date()
            try repository.updateContext(renamed)
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
        let alert = NSAlert()
        alert.messageText = "Delete Context"
        alert.informativeText = "Move \"\(context.title)\" and its snapshots to Trash?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
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

    private func makeBadgeLabel(text: String, emphasis: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = emphasis ? NSColor.white : NSColor.secondaryLabelColor
        label.wantsLayer = true
        label.layer?.cornerRadius = 8
        label.layer?.masksToBounds = true
        label.layer?.backgroundColor = (emphasis ? NSColor.systemBlue : NSColor.quaternaryLabelColor).cgColor
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
