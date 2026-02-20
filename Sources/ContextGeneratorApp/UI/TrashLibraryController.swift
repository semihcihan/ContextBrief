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
        DispatchQueue.main.async { [weak self] in
            self?.refreshData()
        }
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
        splitView.translatesAutoresizingMaskIntoConstraints = false

        let leftPane = NSView()
        let rightPane = NSView()
        let detailContainer = NSVisualEffectView()
        leftPane.translatesAutoresizingMaskIntoConstraints = false
        rightPane.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.material = .underWindowBackground
        detailContainer.blendingMode = .withinWindow
        detailContainer.state = .active
        detailContainer.wantsLayer = true
        detailContainer.layer?.cornerRadius = 12
        detailContainer.layer?.masksToBounds = true
        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        splitView.addSubview(leftPane)
        splitView.addSubview(rightPane)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("trashColumn"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = max(
            tableView.rowHeight,
            NSFont.preferredFont(forTextStyle: .headline).pointSize + 8
        )
        rowMenu.delegate = self
        rowMenu.autoenablesItems = false
        tableView.menu = rowMenu

        tableScrollView.documentView = tableView
        tableScrollView.hasVerticalScroller = true
        tableScrollView.translatesAutoresizingMaskIntoConstraints = false

        detailTextView.isEditable = false
        detailTextView.textColor = .labelColor
        detailTextView.font = NSFont.preferredFont(forTextStyle: .body)
        detailTextView.isVerticallyResizable = true
        detailTextView.isHorizontallyResizable = false
        detailTextView.autoresizingMask = [.width]
        detailTextView.textContainerInset = NSSize(width: 12, height: 12)
        detailTextView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        detailTextView.textContainer?.widthTracksTextView = true
        detailTextView.drawsBackground = false
        detailTextView.backgroundColor = .clear
        detailScrollView.documentView = detailTextView
        detailScrollView.hasVerticalScroller = true
        detailScrollView.drawsBackground = false
        detailScrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(splitView)
        leftPane.addSubview(tableScrollView)
        rightPane.addSubview(detailContainer)
        detailContainer.addSubview(detailScrollView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            leftPane.widthAnchor.constraint(equalToConstant: 320),

            tableScrollView.topAnchor.constraint(equalTo: leftPane.topAnchor),
            tableScrollView.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            tableScrollView.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            tableScrollView.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor),

            detailContainer.topAnchor.constraint(equalTo: rightPane.topAnchor),
            detailContainer.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: rightPane.bottomAnchor),

            detailScrollView.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            detailScrollView.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailScrollView.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailScrollView.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor)
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
            title.font = NSFont.preferredFont(forTextStyle: .headline)
            title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            stack.addArrangedSubview(badge)
            stack.addArrangedSubview(title)
            created.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: created.leadingAnchor, constant: 6),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: created.trailingAnchor, constant: -6),
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
            title?.font = NSFont.preferredFont(forTextStyle: .headline)
        case .snapshot(let snapshot):
            badge?.stringValue = "Snapshot"
            title?.stringValue = "\(snapshot.snapshot.title) - \(snapshot.sourceContextTitle)"
            let baseSnapshotTitleFont = NSFont.preferredFont(forTextStyle: .subheadline)
            title?.font = NSFont.systemFont(ofSize: baseSnapshotTitleFont.pointSize + 1, weight: .regular)
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        showSelectedDetails()
    }

    private func showSelectedDetails() {
        let titleFont = NSFont.preferredFont(forTextStyle: .title2)
        let bodyFont = NSFont.preferredFont(forTextStyle: .body)
        let sectionTitleFont = NSFont.systemFont(ofSize: bodyFont.pointSize, weight: .semibold)
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, selectedRow < items.count else {
            detailTextView.string = items.isEmpty ? "Trash is empty." : "Select an item."
            return
        }
        switch items[selectedRow] {
        case .context(let context):
            let details = NSMutableAttributedString(
                string: "\(context.context.title)\n",
                attributes: [
                    .font: titleFont,
                    .foregroundColor: NSColor.labelColor
                ]
            )
            details.append(
                NSAttributedString(
                    string: "Type: Context\nSnapshots: \(context.snapshots.count)\nCreated: \(context.context.createdAt.formatted())\nDeleted: \(context.deletedAt.formatted())",
                    attributes: [
                        .font: bodyFont,
                        .foregroundColor: NSColor.labelColor
                    ]
                )
            )
            applyDetailsText(details)
        case .snapshot(let item):
            let snapshot = item.snapshot
            let details = NSMutableAttributedString(
                string: "\(snapshot.title)\n",
                attributes: [
                    .font: titleFont,
                    .foregroundColor: NSColor.labelColor
                ]
            )
            details.append(
                NSAttributedString(
                    string: "Type: Snapshot\nFrom Context: \(item.sourceContextTitle)\nApp: \(snapshot.appName)\nWindow: \(snapshot.windowTitle)\nDeleted: \(item.deletedAt.formatted())",
                    attributes: [
                        .font: bodyFont,
                        .foregroundColor: NSColor.labelColor
                    ]
                )
            )
            if !snapshot.denseContent.isEmpty {
                details.append(
                    NSAttributedString(
                        string: "\n\nDense Content",
                        attributes: [
                            .font: sectionTitleFont,
                            .foregroundColor: NSColor.labelColor
                        ]
                    )
                )
                details.append(
                    NSAttributedString(
                        string: "\n\(snapshot.denseContent)",
                        attributes: [
                            .font: bodyFont,
                            .foregroundColor: NSColor.labelColor
                        ]
                    )
                )
            }
            if !snapshot.rawContent.isEmpty {
                details.append(
                    NSAttributedString(
                        string: "\n\nRaw Content",
                        attributes: [
                            .font: sectionTitleFont,
                            .foregroundColor: NSColor.labelColor
                        ]
                    )
                )
                details.append(
                    NSAttributedString(
                        string: "\n\(snapshot.rawContent)",
                        attributes: [
                            .font: bodyFont,
                            .foregroundColor: NSColor.labelColor
                        ]
                    )
                )
            }
            if snapshot.denseContent.isEmpty, snapshot.rawContent.isEmpty {
                details.append(
                    NSAttributedString(
                        string: "\n\nNo content available.",
                        attributes: [
                            .font: bodyFont,
                            .foregroundColor: NSColor.secondaryLabelColor
                        ]
                    )
                )
            }
            applyDetailsText(details)
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
        let badgeFont = NSFont.preferredFont(forTextStyle: .subheadline)
        label.font = NSFont.systemFont(ofSize: badgeFont.pointSize, weight: .semibold)
        label.textColor = NSColor.secondaryLabelColor
        label.wantsLayer = true
        label.layer?.cornerRadius = 8
        label.layer?.masksToBounds = true
        label.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        label.alignment = .center
        label.cell?.usesSingleLineMode = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.heightAnchor.constraint(greaterThanOrEqualToConstant: ceil(badgeFont.pointSize + 6)).isActive = true
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        return label
    }

    private func applyDetailsText(_ details: NSAttributedString) {
        if let textStorage = detailTextView.textStorage {
            textStorage.setAttributedString(details)
            return
        }
        detailTextView.string = details.string
    }
}
