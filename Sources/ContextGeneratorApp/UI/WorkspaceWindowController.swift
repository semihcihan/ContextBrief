import AppKit
import ContextGenerator

final class WorkspaceWindowController: NSWindowController {
    enum Section: Int, CaseIterable {
        case setup
        case contextLibrary
        case trash

        var title: String {
            switch self {
            case .setup:
                return "Setup"
            case .contextLibrary:
                return "Context Library"
            case .trash:
                return "Trash"
            }
        }

        var symbolName: String {
            switch self {
            case .setup:
                return "slider.horizontal.3"
            case .contextLibrary:
                return "books.vertical"
            case .trash:
                return "trash"
            }
        }
    }

    private let sidebarController = WorkspaceSidebarViewController()
    private let contentHostController = WorkspaceContentHostController()
    private let setupController: SetupViewController
    private let contextLibraryController: ContextLibraryController
    private let trashLibraryController: TrashLibraryController
    private let notificationCenter: NotificationCenter
    private var selectedSection: Section = .setup

    init(
        permissionService: PermissionServicing,
        appStateService: AppStateService,
        repository: ContextRepositorying,
        sessionManager: ContextSessionManager,
        onSetupComplete: @escaping () -> Void,
        onSelectionChange: @escaping (String) -> Void,
        notificationCenter: NotificationCenter = .default
    ) {
        self.notificationCenter = notificationCenter
        setupController = SetupViewController(
            permissionService: permissionService,
            appStateService: appStateService,
            onComplete: onSetupComplete
        )
        contextLibraryController = ContextLibraryController(
            repository: repository,
            sessionManager: sessionManager,
            onSelectionChange: onSelectionChange
        )
        trashLibraryController = TrashLibraryController(
            sessionManager: sessionManager,
            onSelectionChange: onSelectionChange
        )

        let splitController = NSSplitViewController()
        splitController.splitViewItems = [
            NSSplitViewItem(sidebarWithViewController: sidebarController),
            NSSplitViewItem(viewController: contentHostController)
        ]
        splitController.splitViewItems[0].minimumThickness = 180
        splitController.splitViewItems[0].maximumThickness = 240
        splitController.splitViewItems[0].canCollapse = false

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Context Generator"
        window.minSize = NSSize(width: 840, height: 520)
        window.contentViewController = splitController
        window.toolbarStyle = .unified
        super.init(window: window)
        notificationCenter.addObserver(
            self,
            selector: #selector(handleContextDataDidChange),
            name: .contextDataDidChange,
            object: nil
        )

        sidebarController.configure(
            items: Section.allCases.map { section in
                SidebarItem(section: section.rawValue, title: section.title, symbolName: section.symbolName)
            }
        ) { [weak self] index in
            guard let section = Section(rawValue: index) else {
                return
            }
            self?.select(section)
        }
        select(.setup)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    func show(section: Section, sender: Any?) {
        select(section)
        presentWindowAsFrontmost(sender)
    }

    func refreshVisibleSection() {
        switch selectedSection {
        case .setup:
            return
        case .contextLibrary:
            contextLibraryController.refreshData()
        case .trash:
            trashLibraryController.refreshData()
        }
    }

    @objc private func handleContextDataDidChange() {
        refreshVisibleSection()
    }

    private func select(_ section: Section) {
        selectedSection = section
        sidebarController.select(index: section.rawValue)
        switch section {
        case .setup:
            contentHostController.show(setupController)
        case .contextLibrary:
            contextLibraryController.refreshData()
            contentHostController.show(contextLibraryController)
        case .trash:
            trashLibraryController.refreshData()
            contentHostController.show(trashLibraryController)
        }
    }
}

private final class WorkspaceSidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private var items: [SidebarItem] = []
    private var onSelect: ((Int) -> Void)?
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.delegate = self
        tableView.dataSource = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func configure(items: [SidebarItem], onSelect: @escaping (Int) -> Void) {
        self.items = items
        self.onSelect = onSelect
        if isViewLoaded {
            tableView.reloadData()
        }
    }

    func select(index: Int) {
        guard let row = items.firstIndex(where: { $0.section == index }) else {
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let identifier = NSUserInterfaceItemIdentifier("sidebarRow")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let created = NSTableCellView()
            created.identifier = identifier

            let icon = NSImageView()
            icon.identifier = NSUserInterfaceItemIdentifier("icon")
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            icon.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            created.textField = label
            created.addSubview(icon)
            created.addSubview(label)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: created.leadingAnchor, constant: 10),
                icon.centerYAnchor.constraint(equalTo: created.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 15),
                icon.heightAnchor.constraint(equalToConstant: 15),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: created.trailingAnchor, constant: -10),
                label.centerYAnchor.constraint(equalTo: created.centerYAnchor)
            ])
            return created
        }()
        cell.textField?.stringValue = item.title
        if let icon = cell.subviews.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("icon") }) as? NSImageView {
            icon.image = NSImage(systemSymbolName: item.symbolName, accessibilityDescription: item.title)
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let index = tableView.selectedRow
        guard index >= 0 else {
            return
        }
        onSelect?(items[index].section)
    }
}

private struct SidebarItem {
    let section: Int
    let title: String
    let symbolName: String
}

private final class WorkspaceContentHostController: NSViewController {
    override func loadView() {
        view = NSView()
    }

    func show(_ controller: NSViewController) {
        children.forEach { existing in
            existing.view.removeFromSuperview()
            existing.removeFromParent()
        }
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
