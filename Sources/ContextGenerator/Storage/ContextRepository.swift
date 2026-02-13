import Foundation

public protocol ContextRepositorying {
    func appState() throws -> AppState
    func saveAppState(_ state: AppState) throws

    func listContexts() throws -> [Context]
    func context(id: UUID) throws -> Context?
    func createContext(title: String) throws -> Context
    func updateContext(_ context: Context) throws

    func pieces(in contextId: UUID) throws -> [CapturePiece]
    func appendPiece(_ piece: CapturePiece) throws
    func removeLastPiece(in contextId: UUID) throws -> CapturePiece?
    func lastPiece(in contextId: UUID) throws -> CapturePiece?
    func removePiece(id: UUID) throws

    func saveScreenshotData(_ data: Data, pieceId: UUID) throws
    func screenshotData(pieceId: UUID) throws -> Data?
}

private struct PersistedStore: Codable {
    var appState: AppState
    var contexts: [Context]
    var pieces: [CapturePiece]
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

    public func pieces(in contextId: UUID) throws -> [CapturePiece] {
        try readStore()
            .pieces
            .filter { $0.contextId == contextId }
            .sorted { $0.sequence < $1.sequence }
    }

    public func appendPiece(_ piece: CapturePiece) throws {
        try mutateStore {
            $0.pieces.append(piece)
            if let contextIndex = $0.contexts.firstIndex(where: { $0.id == piece.contextId }) {
                $0.contexts[contextIndex].pieceCount += 1
                $0.contexts[contextIndex].updatedAt = Date()
            }
        }
    }

    public func removeLastPiece(in contextId: UUID) throws -> CapturePiece? {
        var removed: CapturePiece?
        try mutateStore {
            let contextPieces =
                $0.pieces
                .enumerated()
                .filter { $0.element.contextId == contextId }
                .sorted(by: { $0.element.sequence > $1.element.sequence })
            guard let last = contextPieces.first else {
                return
            }

            removed = $0.pieces.remove(at: last.offset)
            if let contextIndex = $0.contexts.firstIndex(where: { $0.id == contextId }) {
                $0.contexts[contextIndex].pieceCount = max(0, $0.contexts[contextIndex].pieceCount - 1)
                $0.contexts[contextIndex].updatedAt = Date()
            }
        }
        return removed
    }

    public func lastPiece(in contextId: UUID) throws -> CapturePiece? {
        try pieces(in: contextId).last
    }

    public func removePiece(id: UUID) throws {
        try mutateStore {
            guard let index = $0.pieces.firstIndex(where: { $0.id == id }) else {
                return
            }

            let removed = $0.pieces.remove(at: index)
            if let contextIndex = $0.contexts.firstIndex(where: { $0.id == removed.contextId }) {
                $0.contexts[contextIndex].pieceCount = max(0, $0.contexts[contextIndex].pieceCount - 1)
                $0.contexts[contextIndex].updatedAt = Date()
            }
        }
    }

    public func saveScreenshotData(_ data: Data, pieceId: UUID) throws {
        try FileManager.default.createDirectory(at: artifactsURL, withIntermediateDirectories: true)
        try data.write(to: screenshotURL(pieceId: pieceId), options: .atomic)
    }

    public func screenshotData(pieceId: UUID) throws -> Data? {
        let url = screenshotURL(pieceId: pieceId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    private func screenshotURL(pieceId: UUID) -> URL {
        artifactsURL.appendingPathComponent("\(pieceId.uuidString).png")
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
            let initialStore = PersistedStore(appState: AppState(), contexts: [], pieces: [])
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
