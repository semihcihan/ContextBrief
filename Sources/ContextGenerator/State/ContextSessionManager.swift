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

    public func appendSnapshot(
        rawCapture: CapturedSnapshot,
        denseContent: String,
        provider: ProviderName?,
        model: String?,
        status: SnapshotStatus = .ready,
        failureMessage: String? = nil,
        retryCount: Int = 0,
        lastAttemptAt: Date? = nil
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
            processingDurationMs: rawCapture.diagnostics.processingDurationMs,
            status: status,
            failureMessage: failureMessage,
            retryCount: retryCount,
            lastAttemptAt: lastAttemptAt
        )
        try repository.appendSnapshot(snapshot)
        return snapshot
    }

    public func hasFailedSnapshotsInCurrentContext() throws -> Bool {
        guard let context = try currentContextIfExists() else {
            return false
        }
        return try repository.snapshots(in: context.id).contains(where: { $0.status == .failed })
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
            model: last.model,
            accessibilityLineCount: last.accessibilityLineCount,
            ocrLineCount: last.ocrLineCount,
            processingDurationMs: last.processingDurationMs,
            status: last.status,
            failureMessage: last.failureMessage,
            retryCount: last.retryCount,
            lastAttemptAt: last.lastAttemptAt
        )
        try repository.appendSnapshot(promotedSnapshot)
        return newContext
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
    public func moveSnapshotToNewContext(_ snapshotId: UUID, title: String? = nil) throws -> (snapshot: Snapshot, context: Context) {
        let context = try createNewContext(title: title)
        guard let moved = try repository.moveSnapshot(id: snapshotId, to: context.id) else {
            throw AppError.snapshotNotFound
        }
        return (moved, context)
    }

    @discardableResult
    public func restoreTrashedContext(_ trashedContextId: UUID, setAsCurrent: Bool = false) throws -> Context {
        let restored = try repository.restoreTrashedContext(id: trashedContextId)
        if setAsCurrent {
            try setCurrentContext(restored.id)
        }
        return restored
    }

    public func deleteTrashedSnapshotPermanently(_ trashedSnapshotId: UUID) throws {
        guard try repository.deleteTrashedSnapshot(id: trashedSnapshotId) else {
            throw AppError.snapshotNotFound
        }
    }

    public func deleteTrashedContextPermanently(_ trashedContextId: UUID) throws {
        guard try repository.deleteTrashedContext(id: trashedContextId) else {
            throw AppError.contextNotFound
        }
    }

    @discardableResult
    public func renameContext(_ contextId: UUID, title: String) throws -> Context {
        guard var context = try repository.context(id: contextId) else {
            throw AppError.contextNotFound
        }
        context.title = title
        context.updatedAt = Date()
        try repository.updateContext(context)
        return context
    }

    @discardableResult
    public func renameSnapshot(_ snapshotId: UUID, title: String) throws -> Snapshot {
        let contexts = try repository.listContexts()
        for context in contexts {
            guard let snapshot = try repository.snapshots(in: context.id).first(where: { $0.id == snapshotId }) else {
                continue
            }
            var renamed = snapshot
            renamed.title = title
            try repository.updateSnapshot(renamed)
            return renamed
        }
        throw AppError.snapshotNotFound
    }
}
