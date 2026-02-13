import AppKit
import ContextGenerator

final class ContextLibraryController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let repository: ContextRepositorying
    private let sessionManager: ContextSessionManager
    private let onSelectionChange: (String) -> Void
    private var contexts: [Context] = []

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

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
        window?.makeKeyAndOrderFront(sender)
    }

    private func setupUI() {
        guard let contentView = window?.contentView else {
            return
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("context"))
        column.title = "Contexts"
        column.width = 520
        tableView.addTableColumn(column)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView = nil

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let useButton = NSButton(title: "Set As Current", target: self, action: #selector(setCurrentContext))
        let addButton = NSButton(title: "New Context", target: self, action: #selector(createContext))
        let stack = NSStackView(views: [useButton, addButton])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(scrollView)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: stack.topAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    private func reloadContexts() {
        do {
            contexts = try repository.listContexts()
            tableView.reloadData()
        } catch {
            onSelectionChange("Failed loading contexts: \(error.localizedDescription)")
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        contexts.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = contexts[row]
        let identifier = NSUserInterfaceItemIdentifier("contextCell")
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

        view.textField?.stringValue = "\(item.title) - \(item.pieceCount) pieces"
        return view
    }

    @objc private func setCurrentContext() {
        let selected = tableView.selectedRow
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
            _ = try sessionManager.createNewContext()
            reloadContexts()
            onSelectionChange("Created and selected new context")
        } catch {
            onSelectionChange("Create context failed: \(error.localizedDescription)")
        }
    }
}
