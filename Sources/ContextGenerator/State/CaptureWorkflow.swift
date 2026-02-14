import Foundation

public struct CaptureWorkflowResult {
    public let context: Context
    public let snapshot: Snapshot
    public let capturedSnapshot: CapturedSnapshot
}

public final class CaptureWorkflow {
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
        guard let provider = state.selectedProvider, let model = state.selectedModel else {
            throw AppError.providerNotConfigured
        }

        guard let key = try keychain.get("api.\(provider.rawValue)") else {
            throw AppError.keyNotConfigured
        }

        let dense = try await densificationService.densify(
            snapshot: capturedSnapshot,
            provider: provider,
            model: model,
            apiKey: key
        )
        let snapshot = try sessionManager.appendSnapshot(
            rawCapture: capturedSnapshot,
            denseContent: dense,
            provider: provider,
            model: model
        )

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
}
