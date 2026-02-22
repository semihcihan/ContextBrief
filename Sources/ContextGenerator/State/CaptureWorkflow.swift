import Foundation

public struct CaptureWorkflowResult {
    public let context: Context
    public let snapshot: Snapshot
    public let capturedSnapshot: CapturedSnapshot
    public let suggestedSnapshotTitle: String?
}

public final class CaptureWorkflow {
    private enum DensificationOutcome {
        case success(content: String, title: String?, retriesPerformed: Int)
        case failed(message: String, retriesPerformed: Int)
    }

    private let maxDensificationAttempts = 2
    private let densificationRetryDelayNanoseconds: UInt64 = 500_000_000
    private let sessionManager: ContextSessionManager
    private let repository: ContextRepositorying
    private let densificationService: Densifying

    public init(
        sessionManager: ContextSessionManager,
        repository: ContextRepositorying,
        densificationService: Densifying
    ) {
        self.sessionManager = sessionManager
        self.repository = repository
        self.densificationService = densificationService
    }

    public func runCapture(
        capturedSnapshot: CapturedSnapshot,
        screenshotData: Data?
    ) async throws -> CaptureWorkflowResult {
        let state = try repository.appState()
        guard
            let selectedProvider = state.selectedProvider,
            selectedProvider.isCLIProvider
        else {
            throw AppError.providerNotConfigured
        }
        let provider = DevelopmentConfig.shared.providerForDensification(selectedProvider: selectedProvider)
        let model = state.selectedModel ?? ""

        let snapshot: Snapshot
        let suggestedTitle: String?
        switch await densifyWithRetry(
            snapshot: capturedSnapshot,
            provider: provider,
            model: model
        ) {
        case .success(let dense, let title, let retriesPerformed):
            suggestedTitle = title
            snapshot = try sessionManager.appendSnapshot(
                rawCapture: capturedSnapshot,
                denseContent: dense,
                provider: provider,
                model: model,
                status: .ready,
                retryCount: retriesPerformed,
                lastAttemptAt: Date()
            )
        case .failed(let message, let retriesPerformed):
            suggestedTitle = nil
            snapshot = try sessionManager.appendSnapshot(
                rawCapture: capturedSnapshot,
                denseContent: "",
                provider: provider,
                model: model,
                status: .failed,
                failureMessage: message,
                retryCount: retriesPerformed,
                lastAttemptAt: Date()
            )
        }

        if let screenshotData {
            try repository.saveScreenshotData(screenshotData, snapshotId: snapshot.id)
        }

        let context = try repository.context(id: snapshot.contextId) ?? sessionManager.currentContext()
        return CaptureWorkflowResult(
            context: context,
            snapshot: snapshot,
            capturedSnapshot: capturedSnapshot,
            suggestedSnapshotTitle: suggestedTitle
        )
    }

    private func densifyWithRetry(
        snapshot: CapturedSnapshot,
        provider: ProviderName,
        model: String
    ) async -> DensificationOutcome {
        var retriesPerformed = 0
        for attempt in 1 ... maxDensificationAttempts {
            do {
                let (dense, title) = try await densificationService.densify(
                    snapshot: snapshot,
                    provider: provider,
                    model: model
                )
                AppLogger.debug(
                    "Densification succeeded [provider=\(provider.rawValue) retriesPerformed=\(retriesPerformed) snapshot=\(snapshot.id.uuidString)]"
                )
                return .success(content: dense, title: title, retriesPerformed: retriesPerformed)
            } catch {
                if attempt < maxDensificationAttempts, shouldRetryDensification(after: error) {
                    retriesPerformed += 1
                    AppLogger.error(
                        "Densification failed, retrying [provider=\(provider.rawValue) attempt=\(attempt) nextAttempt=\(attempt + 1) maxAttempts=\(maxDensificationAttempts) snapshot=\(snapshot.id.uuidString) error=\(errorMessage(from: error))]"
                    )
                    try? await Task.sleep(nanoseconds: densificationRetryDelayNanoseconds)
                    continue
                }
                AppLogger.error(
                    "Densification failed without recovery [provider=\(provider.rawValue) attempt=\(attempt) maxAttempts=\(maxDensificationAttempts) snapshot=\(snapshot.id.uuidString) error=\(errorMessage(from: error))]"
                )
                return .failed(
                    message: errorMessage(from: error),
                    retriesPerformed: retriesPerformed
                )
            }
        }
        return .failed(
            message: "Densification failed.",
            retriesPerformed: retriesPerformed
        )
    }

    private func shouldRetryDensification(after error: Error) -> Bool {
        guard let appError = error as? AppError else {
            return false
        }
        return appError.isRetryableProviderFailure
    }

    private func errorMessage(from error: Error) -> String {
        if let appError = error as? AppError {
            return appError.localizedDescription
        }
        return error.localizedDescription
    }
}
