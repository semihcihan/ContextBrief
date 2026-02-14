import Foundation

public final class ContextSessionManager {
    private let repository: ContextRepositorying

    public init(repository: ContextRepositorying) {
        self.repository = repository
    }

    @discardableResult
    public func createNewContext(title: String? = nil) throws -> Context {
        let all = try repository.listContexts()
        let name = title ?? "Context \(all.count + 1)"
        let created = try repository.createContext(title: name)
        var state = try repository.appState()
        state.currentContextId = created.id
        try repository.saveAppState(state)
        return created
    }

    public func setCurrentContext(_ contextId: UUID) throws {
        guard try repository.context(id: contextId) != nil else {
            throw AppError.contextNotFound
        }
        var state = try repository.appState()
        state.currentContextId = contextId
        try repository.saveAppState(state)
    }

    public func currentContext() throws -> Context {
        let state = try repository.appState()
        if let contextId = state.currentContextId, let context = try repository.context(id: contextId) {
            return context
        }
        return try createNewContext()
    }

    public func currentContextIfExists() throws -> Context? {
        let state = try repository.appState()
        guard let contextId = state.currentContextId else {
            return nil
        }
        return try repository.context(id: contextId)
    }

    public func snapshotsInCurrentContext() throws -> [Snapshot] {
        try repository.snapshots(in: currentContext().id)
    }

    public func hasLastSnapshotInCurrentContext() throws -> Bool {
        try repository.lastSnapshot(in: currentContext().id) != nil
    }

    public func appendSnapshot(
        rawCapture: CapturedSnapshot,
        denseContent: String,
        provider: ProviderName?,
        model: String?
    ) throws -> Snapshot {
        let context = try currentContext()
        let sequence = (try repository.lastSnapshot(in: context.id)?.sequence ?? 0) + 1
        let snapshot = Snapshot(
            contextId: context.id,
            sequence: sequence,
            title: "Snapshot \(sequence)",
            sourceType: rawCapture.sourceType,
            appName: rawCapture.appName,
            bundleIdentifier: rawCapture.bundleIdentifier,
            windowTitle: rawCapture.windowTitle,
            captureMethod: rawCapture.captureMethod,
            rawContent: rawCapture.combinedText,
            ocrContent: rawCapture.ocrText,
            denseContent: denseContent,
            provider: provider?.rawValue,
            model: model,
            accessibilityLineCount: rawCapture.diagnostics.accessibilityLineCount,
            ocrLineCount: rawCapture.diagnostics.ocrLineCount,
            processingDurationMs: rawCapture.diagnostics.processingDurationMs
        )
        try repository.appendSnapshot(snapshot)
        return snapshot
    }

    public func undoLastCaptureInCurrentContext() throws -> Snapshot {
        let context = try currentContext()
        guard let removed = try repository.moveLastSnapshotToTrash(in: context.id)?.snapshot else {
            throw AppError.noCaptureToUndo
        }
        return removed
    }

    @discardableResult
    public func promoteLastCaptureToNewContext(title: String? = nil) throws -> Context {
        let context = try currentContext()
        guard let last = try repository.removeLastSnapshot(in: context.id) else {
            throw AppError.noCaptureToPromote
        }

        let newContext = try createNewContext(title: title)
        let promotedSnapshot = Snapshot(
            contextId: newContext.id,
            sequence: 1,
            title: last.title,
            sourceType: last.sourceType,
            appName: last.appName,
            bundleIdentifier: last.bundleIdentifier,
            windowTitle: last.windowTitle,
            captureMethod: last.captureMethod,
            rawContent: last.rawContent,
            ocrContent: last.ocrContent,
            denseContent: last.denseContent,
            provider: last.provider,
            model: last.model
        )
        try repository.appendSnapshot(promotedSnapshot)
        return newContext
    }

    public func renameCurrentContext(_ title: String) throws {
        var context = try currentContext()
        context.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        context.updatedAt = Date()
        try repository.updateContext(context)
    }

    public func renameSnapshot(_ snapshotId: UUID, title: String) throws {
        guard var snapshot = try snapshotsInCurrentContext().first(where: { $0.id == snapshotId }) else {
            throw AppError.snapshotNotFound
        }
        snapshot.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        try repository.updateSnapshot(snapshot)
    }

    @discardableResult
    public func deleteContextToTrash(_ contextId: UUID) throws -> Int {
        let removed = try repository.moveContextSnapshotsToTrash(contextId: contextId)
        return removed.count
    }

    @discardableResult
    public func deleteSnapshotToTrash(_ snapshotId: UUID) throws -> Snapshot {
        guard let trashed = try repository.moveSnapshotToTrash(id: snapshotId) else {
            throw AppError.snapshotNotFound
        }
        return trashed.snapshot
    }

    public func trashedSnapshots() throws -> [TrashedSnapshot] {
        try repository.trashSnapshots()
    }

    public func trashedContexts() throws -> [TrashedContext] {
        try repository.trashedContexts()
    }

    @discardableResult
    public func restoreTrashedSnapshotToCurrentContext(_ trashedSnapshotId: UUID) throws -> Snapshot {
        let context = try currentContext()
        return try repository.restoreTrashedSnapshot(id: trashedSnapshotId, to: context.id)
    }

    @discardableResult
    public func moveSnapshotToCurrentContext(_ snapshotId: UUID) throws -> Snapshot {
        let context = try currentContext()
        guard let moved = try repository.moveSnapshot(id: snapshotId, to: context.id) else {
            throw AppError.snapshotNotFound
        }
        return moved
    }

    @discardableResult
    public func restoreTrashedContext(_ trashedContextId: UUID, setAsCurrent: Bool = false) throws -> Context {
        let restored = try repository.restoreTrashedContext(id: trashedContextId)
        if setAsCurrent {
            try setCurrentContext(restored.id)
        }
        return restored
    }
}
