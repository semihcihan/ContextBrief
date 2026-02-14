import AppKit
import ContextGenerator

final class ContextLibraryController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let repository: ContextRepositorying
    private let sessionManager: ContextSessionManager
    private let onSelectionChange: (String) -> Void
    private var contexts: [Context] = []
    private var snapshots: [Snapshot] = []

    private let contextsTableView = NSTableView()
    private let snapshotsTableView = NSTableView()
    private let contextScrollView = NSScrollView()
    private let snapshotsScrollView = NSScrollView()
    private let snapshotTextView = NSTextView()
    private let snapshotTextScrollView = NSScrollView()
    private let setCurrentButton = NSButton(title: "Set As Current", target: nil, action: nil)
    private let addButton = NSButton(title: "New Context", target: nil, action: nil)
    private let renameButton = NSButton(title: "Rename Context", target: nil, action: nil)

    init(
        repository: ContextRepositorying,
        sessionManager: ContextSessionManager,
        onSelectionChange: @escaping (String) -> Void
    ) {
        self.repository = repository
        self.sessionManager = sessionManager
        self.onSelectionChange = onSelectionChange

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Context Library"
        super.init(window: window)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        reloadContexts()
        super.showWindow(sender)
        presentWindowAsFrontmost(sender)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else {
            return
        }

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

        let contextsColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("contextsColumn"))
        contextsColumn.title = "Contexts"
        contextsTableView.addTableColumn(contextsColumn)
        contextsTableView.delegate = self
        contextsTableView.dataSource = self
        contextsTableView.headerView = nil
        contextsTableView.usesAlternatingRowBackgroundColors = true

        contextScrollView.documentView = contextsTableView
        contextScrollView.hasVerticalScroller = true
        contextScrollView.translatesAutoresizingMaskIntoConstraints = false

        setCurrentButton.target = self
        setCurrentButton.action = #selector(setCurrentContext)
        addButton.target = self
        addButton.action = #selector(createContext)
        renameButton.target = self
        renameButton.action = #selector(renameContext)

        let leftButtons = NSStackView(views: [setCurrentButton, addButton, renameButton])
        leftButtons.orientation = .horizontal
        leftButtons.spacing = 8
        leftButtons.translatesAutoresizingMaskIntoConstraints = false

        let snapshotsColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("snapshotsColumn"))
        snapshotsColumn.title = "Snapshots"
        snapshotsTableView.addTableColumn(snapshotsColumn)
        snapshotsTableView.delegate = self
        snapshotsTableView.dataSource = self
        snapshotsTableView.headerView = nil
        snapshotsTableView.usesAlternatingRowBackgroundColors = true

        snapshotsScrollView.documentView = snapshotsTableView
        snapshotsScrollView.hasVerticalScroller = true
        snapshotsScrollView.translatesAutoresizingMaskIntoConstraints = false

        snapshotTextView.isEditable = false
        snapshotTextView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        snapshotTextScrollView.documentView = snapshotTextView
        snapshotTextScrollView.hasVerticalScroller = true
        snapshotTextScrollView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(splitView)
        leftPane.addSubview(contextScrollView)
        leftPane.addSubview(leftButtons)
        rightPane.addSubview(snapshotsScrollView)
        rightPane.addSubview(snapshotTextScrollView)

        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            leftPane.widthAnchor.constraint(equalToConstant: 280),

            contextScrollView.topAnchor.constraint(equalTo: leftPane.topAnchor),
            contextScrollView.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            contextScrollView.trailingAnchor.constraint(equalTo: leftPane.trailingAnchor),
            contextScrollView.bottomAnchor.constraint(equalTo: leftButtons.topAnchor, constant: -12),
            leftButtons.leadingAnchor.constraint(equalTo: leftPane.leadingAnchor),
            leftButtons.trailingAnchor.constraint(lessThanOrEqualTo: leftPane.trailingAnchor),
            leftButtons.bottomAnchor.constraint(equalTo: leftPane.bottomAnchor),

            snapshotsScrollView.topAnchor.constraint(equalTo: rightPane.topAnchor),
            snapshotsScrollView.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            snapshotsScrollView.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            snapshotsScrollView.heightAnchor.constraint(equalToConstant: 150),

            snapshotTextScrollView.topAnchor.constraint(equalTo: snapshotsScrollView.bottomAnchor, constant: 12),
            snapshotTextScrollView.leadingAnchor.constraint(equalTo: rightPane.leadingAnchor),
            snapshotTextScrollView.trailingAnchor.constraint(equalTo: rightPane.trailingAnchor),
            snapshotTextScrollView.bottomAnchor.constraint(equalTo: rightPane.bottomAnchor)
        ])

        updateActionButtons()
    }

    private func reloadContexts() {
        do {
            contexts = try repository.listContexts()
            contextsTableView.reloadData()
            if !contexts.isEmpty {
                let selectedRow = max(0, min(contextsTableView.selectedRow, contexts.count - 1))
                contextsTableView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
                reloadSnapshotsForSelectedContext()
            } else {
                snapshots = []
                snapshotsTableView.reloadData()
                snapshotTextView.string = "No context selected."
            }
            updateActionButtons()
        } catch {
            onSelectionChange("Failed loading contexts: \(error.localizedDescription)")
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView == contextsTableView ? contexts.count : snapshots.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier(tableView == contextsTableView ? "contextCell" : "snapshotCell")
        let view = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }()

        if tableView == contextsTableView {
            let item = contexts[row]
            view.textField?.stringValue = "\(item.title) - \(item.snapshotCount) snapshots"
        } else {
            let snapshot = snapshots[row]
            view.textField?.stringValue = "\(snapshot.sequence). \(snapshot.title)"
        }
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let selectedTable = notification.object as? NSTableView else {
            return
        }
        if selectedTable == contextsTableView {
            reloadSnapshotsForSelectedContext()
        } else if selectedTable == snapshotsTableView {
            showSelectedSnapshotText()
        }
        updateActionButtons()
    }

    @objc private func setCurrentContext() {
        let selected = contextsTableView.selectedRow
        guard selected >= 0, selected < contexts.count else {
            return
        }

        do {
            let context = contexts[selected]
            try sessionManager.setCurrentContext(context.id)
            onSelectionChange("Current context: \(context.title)")
            close()
        } catch {
            onSelectionChange("Set context failed: \(error.localizedDescription)")
        }
    }

    @objc private func createContext() {
        do {
            _ = try sessionManager.createNewContext(title: "New Context")
            reloadContexts()
            onSelectionChange("Created and selected new context")
        } catch {
            onSelectionChange("Create context failed: \(error.localizedDescription)")
        }
    }

    @objc private func renameContext() {
        let selected = contextsTableView.selectedRow
        guard selected >= 0, selected < contexts.count else {
            return
        }

        let context = contexts[selected]
        let alert = NSAlert()
        alert.messageText = "Rename Context"
        alert.informativeText = "Enter a new context name."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.stringValue = context.title
        alert.accessoryView = input
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
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
            reloadContexts()
            if let index = contexts.firstIndex(where: { $0.id == context.id }) {
                contextsTableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
            }
            onSelectionChange("Renamed context")
        } catch {
            onSelectionChange("Rename failed: \(error.localizedDescription)")
        }
    }

    private func reloadSnapshotsForSelectedContext() {
        let selected = contextsTableView.selectedRow
        guard selected >= 0, selected < contexts.count else {
            snapshots = []
            snapshotsTableView.reloadData()
            snapshotTextView.string = "Select a context to read its snapshots."
            updateActionButtons()
            return
        }

        do {
            snapshots = try repository.snapshots(in: contexts[selected].id)
            snapshotsTableView.reloadData()
            if snapshots.isEmpty {
                snapshotTextView.string = "No snapshots in this context."
            } else {
                let row = max(0, min(snapshotsTableView.selectedRow, snapshots.count - 1))
                snapshotsTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                showSelectedSnapshotText()
            }
        } catch {
            snapshots = []
            snapshotsTableView.reloadData()
            snapshotTextView.string = "Failed to load snapshots."
        }
    }

    private func showSelectedSnapshotText() {
        let selected = snapshotsTableView.selectedRow
        guard selected >= 0, selected < snapshots.count else {
            snapshotTextView.string = snapshots.isEmpty ? "No snapshots in this context." : "Select a snapshot."
            return
        }
        let snapshot = snapshots[selected]
        snapshotTextView.string = [
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

    private func updateActionButtons() {
        let hasContextSelection = contextsTableView.selectedRow >= 0 && contextsTableView.selectedRow < contexts.count
        setCurrentButton.isEnabled = hasContextSelection
        renameButton.isEnabled = hasContextSelection
    }
}
