import Foundation

public protocol ContextRepositorying: Sendable {
    func appState() throws -> AppState
    func saveAppState(_ state: AppState) throws

    func listContexts() throws -> [Context]
    func context(id: UUID) throws -> Context?
    func createContext(title: String) throws -> Context
    func updateContext(_ context: Context) throws

    func snapshot(id: UUID) throws -> Snapshot?
    func snapshots(in contextId: UUID) throws -> [Snapshot]
    func appendSnapshot(_ snapshot: Snapshot) throws
    func updateSnapshot(_ snapshot: Snapshot) throws
    func removeLastSnapshot(in contextId: UUID) throws -> Snapshot?
    func lastSnapshot(in contextId: UUID) throws -> Snapshot?
    func trashSnapshots() throws -> [TrashedSnapshot]
    func moveLastSnapshotToTrash(in contextId: UUID) throws -> TrashedSnapshot?
    func moveSnapshotToTrash(id: UUID) throws -> TrashedSnapshot?
    func moveContextSnapshotsToTrash(contextId: UUID) throws -> [TrashedSnapshot]
    func restoreTrashedSnapshot(id: UUID, to contextId: UUID) throws -> Snapshot
    func moveSnapshot(id: UUID, to contextId: UUID) throws -> Snapshot?
    func trashedContexts() throws -> [TrashedContext]
    func restoreTrashedContext(id: UUID) throws -> Context
    func deleteTrashedSnapshot(id: UUID) throws -> Bool
    func deleteTrashedContext(id: UUID) throws -> Bool

    func saveScreenshotData(_ data: Data, snapshotId: UUID) throws
}

private struct PersistedStore: Codable {
    var appState: AppState
    var contexts: [Context]
    var snapshots: [Snapshot]
    var trashedSnapshots: [TrashedSnapshot]
    var trashedContexts: [TrashedContext]

    init(
        appState: AppState,
        contexts: [Context],
        snapshots: [Snapshot],
        trashedSnapshots: [TrashedSnapshot] = [],
        trashedContexts: [TrashedContext] = []
    ) {
        self.appState = appState
        self.contexts = contexts
        self.snapshots = snapshots
        self.trashedSnapshots = trashedSnapshots
        self.trashedContexts = trashedContexts
    }

    enum CodingKeys: String, CodingKey {
        case appState
        case contexts
        case snapshots
        case trashedSnapshots
        case trashedContexts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appState = try container.decode(AppState.self, forKey: .appState)
        contexts = try container.decode([Context].self, forKey: .contexts)
        snapshots = try container.decode([Snapshot].self, forKey: .snapshots)
        trashedSnapshots = try container.decodeIfPresent([TrashedSnapshot].self, forKey: .trashedSnapshots) ?? []
        trashedContexts = try container.decodeIfPresent([TrashedContext].self, forKey: .trashedContexts) ?? []
    }
}

public final class ContextRepository: ContextRepositorying, @unchecked Sendable {
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
        self.rootURL = baseURL.appendingPathComponent("ContextBrief", isDirectory: true)
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

    public func snapshot(id: UUID) throws -> Snapshot? {
        try readStore().snapshots.first(where: { $0.id == id })
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

    public func trashSnapshots() throws -> [TrashedSnapshot] {
        try readStore()
            .trashedSnapshots
            .sorted { $0.deletedAt > $1.deletedAt }
    }

    public func moveLastSnapshotToTrash(in contextId: UUID) throws -> TrashedSnapshot? {
        var trashed: TrashedSnapshot?
        try mutateStore {
            let contextSnapshots =
                $0.snapshots
                .enumerated()
                .filter { $0.element.contextId == contextId }
                .sorted(by: { $0.element.sequence > $1.element.sequence })
            guard let last = contextSnapshots.first else {
                return
            }
            let removed = $0.snapshots.remove(at: last.offset)
            guard let contextIndex = $0.contexts.firstIndex(where: { $0.id == contextId }) else {
                return
            }
            $0.contexts[contextIndex].snapshotCount = max(0, $0.contexts[contextIndex].snapshotCount - 1)
            $0.contexts[contextIndex].updatedAt = Date()
            trashed = TrashedSnapshot(snapshot: removed, sourceContextTitle: $0.contexts[contextIndex].title)
            if let trashed {
                $0.trashedSnapshots.insert(trashed, at: 0)
            }
        }
        return trashed
    }

    public func moveSnapshotToTrash(id: UUID) throws -> TrashedSnapshot? {
        var trashed: TrashedSnapshot?
        try mutateStore {
            guard let index = $0.snapshots.firstIndex(where: { $0.id == id }) else {
                return
            }
            let removed = $0.snapshots.remove(at: index)
            guard let contextIndex = $0.contexts.firstIndex(where: { $0.id == removed.contextId }) else {
                return
            }
            $0.contexts[contextIndex].snapshotCount = max(0, $0.contexts[contextIndex].snapshotCount - 1)
            $0.contexts[contextIndex].updatedAt = Date()
            trashed = TrashedSnapshot(snapshot: removed, sourceContextTitle: $0.contexts[contextIndex].title)
            if let trashed {
                $0.trashedSnapshots.insert(trashed, at: 0)
            }
        }
        return trashed
    }

    public func moveContextSnapshotsToTrash(contextId: UUID) throws -> [TrashedSnapshot] {
        var removedSnapshots: [TrashedSnapshot] = []
        try mutateStore {
            guard let contextIndex = $0.contexts.firstIndex(where: { $0.id == contextId }) else {
                return
            }
            let context = $0.contexts[contextIndex]
            let removed = $0.snapshots.filter { $0.contextId == contextId }
            removedSnapshots = removed
                .sorted(by: { $0.sequence > $1.sequence })
                .map { TrashedSnapshot(snapshot: $0, sourceContextTitle: context.title) }
            $0.trashedContexts.insert(
                TrashedContext(
                    context: context,
                    snapshots: removed.sorted(by: { $0.sequence < $1.sequence })
                ),
                at: 0
            )
            $0.snapshots.removeAll(where: { $0.contextId == contextId })
            $0.contexts.remove(at: contextIndex)
            if $0.appState.currentContextId == contextId {
                $0.appState.currentContextId = nil
            }
        }
        return removedSnapshots
    }

    public func restoreTrashedSnapshot(id: UUID, to contextId: UUID) throws -> Snapshot {
        var restored: Snapshot?
        try mutateStore {
            guard let contextIndex = $0.contexts.firstIndex(where: { $0.id == contextId }) else {
                return
            }
            guard let trashedIndex = $0.trashedSnapshots.firstIndex(where: { $0.id == id }) else {
                return
            }
            let trashed = $0.trashedSnapshots.remove(at: trashedIndex)
            let nextSequence =
                ($0.snapshots
                    .filter { $0.contextId == contextId }
                    .map(\.sequence)
                    .max() ?? 0) + 1
            let snapshot = Snapshot(
                id: trashed.snapshot.id,
                contextId: contextId,
                createdAt: trashed.snapshot.createdAt,
                sequence: nextSequence,
                title: trashed.snapshot.title,
                sourceType: trashed.snapshot.sourceType,
                appName: trashed.snapshot.appName,
                bundleIdentifier: trashed.snapshot.bundleIdentifier,
                windowTitle: trashed.snapshot.windowTitle,
                captureMethod: trashed.snapshot.captureMethod,
                rawContent: trashed.snapshot.rawContent,
                filteredCombinedText: trashed.snapshot.filteredCombinedText,
                ocrContent: trashed.snapshot.ocrContent,
                denseContent: trashed.snapshot.denseContent,
                provider: trashed.snapshot.provider,
                model: trashed.snapshot.model,
                accessibilityLineCount: trashed.snapshot.accessibilityLineCount,
                ocrLineCount: trashed.snapshot.ocrLineCount,
                processingDurationMs: trashed.snapshot.processingDurationMs,
                status: trashed.snapshot.status,
                failureMessage: trashed.snapshot.failureMessage,
                retryCount: trashed.snapshot.retryCount,
                lastAttemptAt: trashed.snapshot.lastAttemptAt
            )
            $0.snapshots.append(snapshot)
            $0.contexts[contextIndex].snapshotCount += 1
            $0.contexts[contextIndex].updatedAt = Date()
            restored = snapshot
        }
        guard let restored else {
            throw AppError.snapshotNotFound
        }
        return restored
    }

    public func moveSnapshot(id: UUID, to contextId: UUID) throws -> Snapshot? {
        var moved: Snapshot?
        try mutateStore {
            guard let sourceIndex = $0.snapshots.firstIndex(where: { $0.id == id }) else {
                return
            }
            guard let targetContextIndex = $0.contexts.firstIndex(where: { $0.id == contextId }) else {
                return
            }
            let sourceSnapshot = $0.snapshots[sourceIndex]
            guard let sourceContextIndex = $0.contexts.firstIndex(where: { $0.id == sourceSnapshot.contextId }) else {
                return
            }
            let nextSequence =
                ($0.snapshots
                    .filter { $0.contextId == contextId && $0.id != id }
                    .map(\.sequence)
                    .max() ?? 0) + 1

            $0.contexts[sourceContextIndex].snapshotCount = max(0, $0.contexts[sourceContextIndex].snapshotCount - 1)
            $0.contexts[sourceContextIndex].updatedAt = Date()

            let updatedSnapshot = Snapshot(
                id: sourceSnapshot.id,
                contextId: contextId,
                createdAt: sourceSnapshot.createdAt,
                sequence: nextSequence,
                title: sourceSnapshot.title,
                sourceType: sourceSnapshot.sourceType,
                appName: sourceSnapshot.appName,
                bundleIdentifier: sourceSnapshot.bundleIdentifier,
                windowTitle: sourceSnapshot.windowTitle,
                captureMethod: sourceSnapshot.captureMethod,
                rawContent: sourceSnapshot.rawContent,
                filteredCombinedText: sourceSnapshot.filteredCombinedText,
                ocrContent: sourceSnapshot.ocrContent,
                denseContent: sourceSnapshot.denseContent,
                provider: sourceSnapshot.provider,
                model: sourceSnapshot.model,
                accessibilityLineCount: sourceSnapshot.accessibilityLineCount,
                ocrLineCount: sourceSnapshot.ocrLineCount,
                processingDurationMs: sourceSnapshot.processingDurationMs,
                status: sourceSnapshot.status,
                failureMessage: sourceSnapshot.failureMessage,
                retryCount: sourceSnapshot.retryCount,
                lastAttemptAt: sourceSnapshot.lastAttemptAt
            )
            $0.snapshots[sourceIndex] = updatedSnapshot
            $0.contexts[targetContextIndex].snapshotCount += 1
            $0.contexts[targetContextIndex].updatedAt = Date()
            moved = updatedSnapshot
        }
        return moved
    }

    public func trashedContexts() throws -> [TrashedContext] {
        try readStore()
            .trashedContexts
            .sorted { $0.deletedAt > $1.deletedAt }
    }

    public func restoreTrashedContext(id: UUID) throws -> Context {
        var restored: Context?
        try mutateStore {
            guard let trashedIndex = $0.trashedContexts.firstIndex(where: { $0.id == id }) else {
                return
            }
            let trashed = $0.trashedContexts.remove(at: trashedIndex)
            let contextId = $0.contexts.contains(where: { $0.id == trashed.context.id }) ? UUID() : trashed.context.id
            let snapshots = trashed.snapshots.enumerated().map { index, snapshot in
                Snapshot(
                    id: snapshot.id,
                    contextId: contextId,
                    createdAt: snapshot.createdAt,
                    sequence: index + 1,
                    title: snapshot.title,
                    sourceType: snapshot.sourceType,
                    appName: snapshot.appName,
                    bundleIdentifier: snapshot.bundleIdentifier,
                    windowTitle: snapshot.windowTitle,
                    captureMethod: snapshot.captureMethod,
                    rawContent: snapshot.rawContent,
                    filteredCombinedText: snapshot.filteredCombinedText,
                    ocrContent: snapshot.ocrContent,
                    denseContent: snapshot.denseContent,
                    provider: snapshot.provider,
                    model: snapshot.model,
                    accessibilityLineCount: snapshot.accessibilityLineCount,
                    ocrLineCount: snapshot.ocrLineCount,
                    processingDurationMs: snapshot.processingDurationMs,
                    status: snapshot.status,
                    failureMessage: snapshot.failureMessage,
                    retryCount: snapshot.retryCount,
                    lastAttemptAt: snapshot.lastAttemptAt
                )
            }
            let context = Context(
                id: contextId,
                title: trashed.context.title,
                createdAt: trashed.context.createdAt,
                updatedAt: Date(),
                snapshotCount: snapshots.count
            )
            $0.contexts.insert(context, at: 0)
            $0.snapshots.append(contentsOf: snapshots)
            restored = context
        }
        guard let restored else {
            throw AppError.contextNotFound
        }
        return restored
    }

    public func deleteTrashedSnapshot(id: UUID) throws -> Bool {
        var deleted = false
        try mutateStore {
            guard let index = $0.trashedSnapshots.firstIndex(where: { $0.id == id }) else {
                return
            }
            $0.trashedSnapshots.remove(at: index)
            deleted = true
        }
        return deleted
    }

    public func deleteTrashedContext(id: UUID) throws -> Bool {
        var deleted = false
        try mutateStore {
            guard let index = $0.trashedContexts.firstIndex(where: { $0.id == id }) else {
                return
            }
            $0.trashedContexts.remove(at: index)
            deleted = true
        }
        return deleted
    }

    public func saveScreenshotData(_ data: Data, snapshotId: UUID) throws {
        try FileManager.default.createDirectory(at: artifactsURL, withIntermediateDirectories: true)
        try data.write(to: screenshotURL(snapshotId: snapshotId), options: .atomic)
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
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .contextDataDidChange, object: nil)
        }
    }

    private func loadStore() throws -> PersistedStore {
        if !FileManager.default.fileExists(atPath: storeURL.path) {
            let initialStore = PersistedStore(
                appState: AppState(),
                contexts: [],
                snapshots: [],
                trashedSnapshots: [],
                trashedContexts: []
            )
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
