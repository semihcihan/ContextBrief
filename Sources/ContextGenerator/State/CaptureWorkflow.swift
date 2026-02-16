import Foundation

public struct CaptureWorkflowResult {
    public let context: Context
    public let snapshot: Snapshot
    public let capturedSnapshot: CapturedSnapshot
}

public final class CaptureWorkflow {
    private enum DensificationOutcome {
        case success(content: String, retriesPerformed: Int)
        case failed(message: String, retriesPerformed: Int)
    }

    private let maxDensificationAttempts = 2
    private let densificationRetryDelayNanoseconds: UInt64 = 500_000_000
    private let captureService: ContextCapturing
    private let sessionManager: ContextSessionManager
    private let repository: ContextRepositorying
    private let densificationService: Densifying
    private let keychain: KeychainServicing

    public init(
        captureService: ContextCapturing,
        sessionManager: ContextSessionManager,
        repository: ContextRepositorying,
        densificationService: Densifying,
        keychain: KeychainServicing
    ) {
        self.captureService = captureService
        self.sessionManager = sessionManager
        self.repository = repository
        self.densificationService = densificationService
        self.keychain = keychain
    }

    public func runCapture() async throws -> CaptureWorkflowResult {
        let (capturedSnapshot, screenshotData) = try captureService.capture()
        let state = try repository.appState()
        guard let selectedProvider = state.selectedProvider else {
            throw AppError.providerNotConfigured
        }
        let provider = DevelopmentConfig.shared.providerForDensification(selectedProvider: selectedProvider)
        let model = state.selectedModel ?? ""
        guard provider == .apple || !model.isEmpty else {
            throw AppError.providerNotConfigured
        }

        let key = try keychain.get("api.\(provider.rawValue)") ?? ""
        guard provider == .apple || !key.isEmpty else {
            throw AppError.keyNotConfigured
        }

        let snapshot: Snapshot
        switch await densifyWithRetry(
            snapshot: capturedSnapshot,
            provider: provider,
            model: model,
            apiKey: key
        ) {
        case .success(let dense, let retriesPerformed):
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

        let context = try sessionManager.currentContext()
        return CaptureWorkflowResult(
            context: context,
            snapshot: snapshot,
            capturedSnapshot: capturedSnapshot
        )
    }

    private func densifyWithRetry(
        snapshot: CapturedSnapshot,
        provider: ProviderName,
        model: String,
        apiKey: String
    ) async -> DensificationOutcome {
        var retriesPerformed = 0
        for attempt in 1 ... maxDensificationAttempts {
            do {
                let dense = try await densificationService.densify(
                    snapshot: snapshot,
                    provider: provider,
                    model: model,
                    apiKey: apiKey
                )
                return .success(content: dense, retriesPerformed: retriesPerformed)
            } catch {
                if attempt < maxDensificationAttempts, shouldRetryDensification(after: error) {
                    retriesPerformed += 1
                    try? await Task.sleep(nanoseconds: densificationRetryDelayNanoseconds)
                    continue
                }
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
        switch appError {
        case .providerRequestFailed:
            return true
        default:
            return false
        }
    }

    private func errorMessage(from error: Error) -> String {
        if let appError = error as? AppError {
            return appError.localizedDescription
        }
        return error.localizedDescription
    }
}
