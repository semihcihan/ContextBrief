import Foundation

public protocol ContextRepositorying {
    func appState() throws -> AppState
    func saveAppState(_ state: AppState) throws

    func listContexts() throws -> [Context]
    func context(id: UUID) throws -> Context?
    func createContext(title: String) throws -> Context
    func updateContext(_ context: Context) throws

    func snapshots(in contextId: UUID) throws -> [Snapshot]
    func appendSnapshot(_ snapshot: Snapshot) throws
    func updateSnapshot(_ snapshot: Snapshot) throws
    func removeLastSnapshot(in contextId: UUID) throws -> Snapshot?
    func lastSnapshot(in contextId: UUID) throws -> Snapshot?
    func removeSnapshot(id: UUID) throws

    func saveScreenshotData(_ data: Data, snapshotId: UUID) throws
    func screenshotData(snapshotId: UUID) throws -> Data?
}

private struct PersistedStore: Codable {
    var appState: AppState
    var contexts: [Context]
    var snapshots: [Snapshot]
}

public final class ContextRepository: ContextRepositorying {
    private let rootURL: URL
    private let storeURL: URL
    private let artifactsURL: URL
    private let lock = NSLock()
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(rootURL: URL? = nil) {
        let baseURL =
            rootURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        self.rootURL = baseURL.appendingPathComponent("ContextGenerator", isDirectory: true)
        storeURL = self.rootURL.appendingPathComponent("store.json")
        artifactsURL = self.rootURL.appendingPathComponent("artifacts", isDirectory: true)

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        try? FileManager.default.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: artifactsURL, withIntermediateDirectories: true)
    }

    public func appState() throws -> AppState {
        try readStore().appState
    }

    public func saveAppState(_ state: AppState) throws {
        try mutateStore {
            $0.appState = state
        }
    }

    public func listContexts() throws -> [Context] {
        try readStore()
            .contexts
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
    }

    public func context(id: UUID) throws -> Context? {
        try readStore().contexts.first { $0.id == id }
    }

    public func createContext(title: String) throws -> Context {
        var created = Context(title: title)
        try mutateStore {
            $0.contexts.insert(created, at: 0)
            $0.appState.currentContextId = created.id
            $0.contexts = $0.contexts.sorted(by: { $0.updatedAt > $1.updatedAt })
            created = $0.contexts.first(where: { $0.id == created.id }) ?? created
        }
        return created
    }

    public func updateContext(_ context: Context) throws {
        try mutateStore {
            guard let index = $0.contexts.firstIndex(where: { $0.id == context.id }) else {
                return
            }
            $0.contexts[index] = context
        }
    }

    public func snapshots(in contextId: UUID) throws -> [Snapshot] {
        try readStore()
            .snapshots
            .filter { $0.contextId == contextId }
            .sorted { $0.sequence < $1.sequence }
    }

    public func appendSnapshot(_ snapshot: Snapshot) throws {
        try mutateStore {
            $0.snapshots.append(snapshot)
            if let contextIndex = $0.contexts.firstIndex(where: { $0.id == snapshot.contextId }) {
                $0.contexts[contextIndex].snapshotCount += 1
                $0.contexts[contextIndex].updatedAt = Date()
            }
        }
    }

    public func updateSnapshot(_ snapshot: Snapshot) throws {
        try mutateStore {
            guard let index = $0.snapshots.firstIndex(where: { $0.id == snapshot.id }) else {
                return
            }
            $0.snapshots[index] = snapshot
            if let contextIndex = $0.contexts.firstIndex(where: { $0.id == snapshot.contextId }) {
                $0.contexts[contextIndex].updatedAt = Date()
            }
        }
    }

    public func removeLastSnapshot(in contextId: UUID) throws -> Snapshot? {
        var removed: Snapshot?
        try mutateStore {
            let contextSnapshots =
                $0.snapshots
                .enumerated()
                .filter { $0.element.contextId == contextId }
                .sorted(by: { $0.element.sequence > $1.element.sequence })
            guard let last = contextSnapshots.first else {
                return
            }

            removed = $0.snapshots.remove(at: last.offset)
            if let contextIndex = $0.contexts.firstIndex(where: { $0.id == contextId }) {
                $0.contexts[contextIndex].snapshotCount = max(0, $0.contexts[contextIndex].snapshotCount - 1)
                $0.contexts[contextIndex].updatedAt = Date()
            }
        }
        return removed
    }

    public func lastSnapshot(in contextId: UUID) throws -> Snapshot? {
        try snapshots(in: contextId).last
    }

    public func removeSnapshot(id: UUID) throws {
        try mutateStore {
            guard let index = $0.snapshots.firstIndex(where: { $0.id == id }) else {
                return
            }

            let removed = $0.snapshots.remove(at: index)
            if let contextIndex = $0.contexts.firstIndex(where: { $0.id == removed.contextId }) {
                $0.contexts[contextIndex].snapshotCount = max(0, $0.contexts[contextIndex].snapshotCount - 1)
                $0.contexts[contextIndex].updatedAt = Date()
            }
        }
    }

    public func saveScreenshotData(_ data: Data, snapshotId: UUID) throws {
        try FileManager.default.createDirectory(at: artifactsURL, withIntermediateDirectories: true)
        try data.write(to: screenshotURL(snapshotId: snapshotId), options: .atomic)
    }

    public func screenshotData(snapshotId: UUID) throws -> Data? {
        let url = screenshotURL(snapshotId: snapshotId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    private func screenshotURL(snapshotId: UUID) -> URL {
        artifactsURL.appendingPathComponent("\(snapshotId.uuidString).png")
    }

    private func readStore() throws -> PersistedStore {
        lock.lock()
        defer {
            lock.unlock()
        }

        return try loadStore()
    }

    private func mutateStore(_ mutation: (inout PersistedStore) -> Void) throws {
        lock.lock()
        defer {
            lock.unlock()
        }

        var store = try loadStore()
        mutation(&store)
        try saveStore(store)
    }

    private func loadStore() throws -> PersistedStore {
        if !FileManager.default.fileExists(atPath: storeURL.path) {
            let initialStore = PersistedStore(appState: AppState(), contexts: [], snapshots: [])
            try saveStore(initialStore)
            return initialStore
        }

        let data = try Data(contentsOf: storeURL)
        return try decoder.decode(PersistedStore.self, from: data)
    }

    private func saveStore(_ store: PersistedStore) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let data = try encoder.encode(store)
        try data.write(to: storeURL, options: .atomic)
    }
}
