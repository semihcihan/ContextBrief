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

    public func appendCapturePiece(
        rawCapture: CapturedContext,
        denseContent: String,
        provider: ProviderName?,
        model: String?
    ) throws -> CapturePiece {
        let context = try currentContext()
        let sequence = (try repository.lastPiece(in: context.id)?.sequence ?? 0) + 1
        let piece = CapturePiece(
            contextId: context.id,
            sequence: sequence,
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
        try repository.appendPiece(piece)
        return piece
    }

    public func undoLastCaptureInCurrentContext() throws -> CapturePiece {
        let context = try currentContext()
        guard let removed = try repository.removeLastPiece(in: context.id) else {
            throw AppError.noCaptureToUndo
        }
        return removed
    }

    @discardableResult
    public func promoteLastCaptureToNewContext(title: String? = nil) throws -> Context {
        let context = try currentContext()
        guard let last = try repository.removeLastPiece(in: context.id) else {
            throw AppError.noCaptureToPromote
        }

        let newContext = try createNewContext(title: title)
        let promotedPiece = CapturePiece(
            contextId: newContext.id,
            sequence: 1,
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
        try repository.appendPiece(promotedPiece)
        return newContext
    }
}
