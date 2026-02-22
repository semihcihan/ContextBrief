import Foundation

public final class SnapshotRetryWorkflow {
    private let repository: ContextRepositorying
    private let densificationService: Densifying

    public init(
        repository: ContextRepositorying,
        densificationService: Densifying
    ) {
        self.repository = repository
        self.densificationService = densificationService
    }

    @discardableResult
    public func retryFailedSnapshot(_ snapshotId: UUID) async throws -> Snapshot {
        guard let snapshot = try repository.snapshot(id: snapshotId) else {
            throw AppError.snapshotNotFound
        }
        guard snapshot.status == .failed else {
            AppLogger.debug(
                "Skipped retry because snapshot is not failed [snapshot=\(snapshot.id.uuidString) status=\(snapshot.status.rawValue)]"
            )
            return snapshot
        }
        guard
            let providerRawValue = snapshot.provider,
            let provider = ProviderName(rawValue: providerRawValue),
            provider.isCLIProvider
        else {
            throw AppError.providerNotConfigured
        }
        let model = snapshot.model ?? ""

        let nextRetryCount = snapshot.retryCount + 1
        let attemptedAt = Date()
        AppLogger.debug(
            "Retrying failed snapshot [snapshot=\(snapshot.id.uuidString) retryCount=\(nextRetryCount) provider=\(provider.rawValue)]"
        )
        let capturedSnapshot = CapturedSnapshot(
            id: snapshot.id,
            capturedAt: snapshot.createdAt,
            sourceType: snapshot.sourceType,
            appName: snapshot.appName,
            bundleIdentifier: snapshot.bundleIdentifier,
            windowTitle: snapshot.windowTitle,
            captureMethod: snapshot.captureMethod,
            accessibilityText: snapshot.rawContent,
            ocrText: snapshot.ocrContent,
            combinedText: snapshot.rawContent,
            filteredCombinedText: snapshot.filteredCombinedText,
            diagnostics: CaptureDiagnostics(
                accessibilityLineCount: snapshot.accessibilityLineCount,
                ocrLineCount: snapshot.ocrLineCount,
                processingDurationMs: snapshot.processingDurationMs,
                usedFallbackOCR: snapshot.ocrLineCount > 0
            )
        )
        do {
            let (dense, _) = try await densificationService.densify(
                snapshot: capturedSnapshot,
                provider: provider,
                model: model
            )
            let updated = makeUpdatedSnapshot(
                from: snapshot,
                denseContent: dense,
                status: .ready,
                failureMessage: nil,
                retryCount: nextRetryCount,
                lastAttemptAt: attemptedAt
            )
            try repository.updateSnapshot(updated)
            AppLogger.debug(
                "Retry succeeded for snapshot [snapshot=\(snapshot.id.uuidString) retryCount=\(nextRetryCount) provider=\(provider.rawValue)]"
            )
            return updated
        } catch {
            let updated = makeUpdatedSnapshot(
                from: snapshot,
                denseContent: snapshot.denseContent,
                status: .failed,
                failureMessage: errorMessage(from: error),
                retryCount: nextRetryCount,
                lastAttemptAt: attemptedAt
            )
            try repository.updateSnapshot(updated)
            AppLogger.error(
                "Retry failed for snapshot [snapshot=\(snapshot.id.uuidString) retryCount=\(nextRetryCount) provider=\(provider.rawValue) error=\(errorMessage(from: error))]"
            )
            throw error
        }
    }

    private func makeUpdatedSnapshot(
        from snapshot: Snapshot,
        denseContent: String,
        status: SnapshotStatus,
        failureMessage: String?,
        retryCount: Int,
        lastAttemptAt: Date?
    ) -> Snapshot {
        Snapshot(
            id: snapshot.id,
            contextId: snapshot.contextId,
            createdAt: snapshot.createdAt,
            sequence: snapshot.sequence,
            title: snapshot.title,
            sourceType: snapshot.sourceType,
            appName: snapshot.appName,
            bundleIdentifier: snapshot.bundleIdentifier,
            windowTitle: snapshot.windowTitle,
            captureMethod: snapshot.captureMethod,
            rawContent: snapshot.rawContent,
            filteredCombinedText: snapshot.filteredCombinedText,
            ocrContent: snapshot.ocrContent,
            denseContent: denseContent,
            provider: snapshot.provider,
            model: snapshot.model,
            accessibilityLineCount: snapshot.accessibilityLineCount,
            ocrLineCount: snapshot.ocrLineCount,
            processingDurationMs: snapshot.processingDurationMs,
            status: status,
            failureMessage: failureMessage,
            retryCount: retryCount,
            lastAttemptAt: lastAttemptAt
        )
    }

    private func errorMessage(from error: Error) -> String {
        if let appError = error as? AppError {
            return appError.localizedDescription
        }
        return error.localizedDescription
    }
}
