import ContextGenerator
import Foundation

@MainActor
protocol SnapshotProcessingCoordinatorDelegate: AnyObject {
    func snapshotProcessingCoordinatorDidChangeProcessingState(_ coordinator: SnapshotProcessingCoordinator)
    func snapshotProcessingCoordinator(
        _ coordinator: SnapshotProcessingCoordinator,
        didQueueCaptureFrom source: String,
        queuedCount: Int
    )
    func snapshotProcessingCoordinator(
        _ coordinator: SnapshotProcessingCoordinator,
        didStartCaptureFrom source: String
    )
    func snapshotProcessingCoordinator(
        _ coordinator: SnapshotProcessingCoordinator,
        didFinishCaptureFrom source: String,
        result: CaptureWorkflowResult
    )
    func snapshotProcessingCoordinator(
        _ coordinator: SnapshotProcessingCoordinator,
        didFailCaptureFrom source: String,
        stage: SnapshotProcessingCoordinator.CaptureFailureStage,
        error: Error
    )
}

final class SnapshotProcessingCoordinator {
    enum CaptureFailureStage {
        case capture
        case workflow
    }

    enum RetrySelectionResult {
        case noContext
        case noFailedSnapshots
        case snapshotIds([UUID])
    }

    struct RetryBatchResult {
        let succeeded: Int
        let failed: Int
    }

    static let noFailedSnapshotsMessage = "No failed snapshots to retry"

    static func retryingMessage(for count: Int) -> String {
        count == 1
            ? "Retrying 1 failed snapshot..."
            : "Retrying \(count) failed snapshots..."
    }

    static func retrySummaryMessage(_ summary: RetryBatchResult) -> String {
        if summary.failed == 0 {
            return summary.succeeded == 1
                ? "Retried 1 failed snapshot"
                : "Retried \(summary.succeeded) failed snapshots"
        }
        return "Retried \(summary.succeeded), failed \(summary.failed)"
    }

    weak var delegate: (any SnapshotProcessingCoordinatorDelegate)?

    private let captureService: ContextCapturing
    private let captureWorkflow: CaptureWorkflow
    private let retryWorkflow: SnapshotRetryWorkflow
    private let sessionManager: ContextSessionManager
    private let repository: ContextRepositorying
    private let stateQueue = DispatchQueue(label: "com.contextbrief.processing.state")
    private let captureExecutionQueue = DispatchQueue(label: "com.contextbrief.processing.capture", qos: .userInitiated)
    private let retryExecutionQueue = DispatchQueue(label: "com.contextbrief.processing.retry", qos: .userInitiated)
    private let captureQueue: CaptureProcessingQueue
    private var activeRetryOperations = 0

    init(
        captureService: ContextCapturing,
        captureWorkflow: CaptureWorkflow,
        retryWorkflow: SnapshotRetryWorkflow,
        sessionManager: ContextSessionManager,
        repository: ContextRepositorying,
        maxConcurrentCaptureProcesses: Int = SnapshotProcessingCoordinator.defaultMaxConcurrentCaptureProcesses()
    ) {
        self.captureService = captureService
        self.captureWorkflow = captureWorkflow
        self.retryWorkflow = retryWorkflow
        self.sessionManager = sessionManager
        self.repository = repository
        captureQueue = CaptureProcessingQueue(maxConcurrentCaptures: maxConcurrentCaptureProcesses)
    }

    var isCaptureInProgress: Bool {
        stateQueue.sync { captureQueue.isCaptureInProgress }
    }

    var queuedCaptureCount: Int {
        stateQueue.sync { captureQueue.queuedCount }
    }

    var activeRetryCount: Int {
        stateQueue.sync { activeRetryOperations }
    }

    var isAnyProcessing: Bool {
        stateQueue.sync {
            captureQueue.isCaptureInProgress || activeRetryOperations > 0
        }
    }

    func requestCapture(source: String) {
        let request = QueuedCaptureRequest(source: source)
        let requestResult = stateQueue.sync {
            captureQueue.requestCapture(request)
        }
        switch requestResult {
        case .queued(let queuedCount):
            notifyDelegate { delegate in
                delegate.snapshotProcessingCoordinator(
                    self,
                    didQueueCaptureFrom: source,
                    queuedCount: queuedCount
                )
            }
            notifyProcessingStateChanged()
        case .startNow(let captureRequest):
            startCaptureProcessing(captureRequest)
        }
    }

    func retrySelectionForCurrentContext() async throws -> RetrySelectionResult {
        try await withCheckedThrowingContinuation { continuation in
            retryExecutionQueue.async { [sessionManager, repository] in
                do {
                    guard let context = try sessionManager.currentContextIfExists() else {
                        continuation.resume(returning: .noContext)
                        return
                    }
                    let failedSnapshotIds = try repository.snapshots(in: context.id)
                        .filter { $0.status == .failed }
                        .map(\.id)
                    guard !failedSnapshotIds.isEmpty else {
                        continuation.resume(returning: .noFailedSnapshots)
                        return
                    }
                    continuation.resume(returning: .snapshotIds(failedSnapshotIds))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func retrySnapshot(_ snapshotId: UUID) async throws -> Snapshot {
        try await withRetryOperationTracking {
            try await retrySnapshotInBackground(snapshotId)
        }
    }

    func retrySnapshots(_ snapshotIds: [UUID]) async -> RetryBatchResult {
        await withRetryOperationTracking {
            let outcomes = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
                for snapshotId in snapshotIds {
                    group.addTask { [self] in
                        do {
                            _ = try await retrySnapshotInBackground(snapshotId)
                            return true
                        } catch {
                            AppLogger.error(
                                "retryFailedSnapshots failed snapshotId=\(snapshotId.uuidString) error=\(error.localizedDescription)"
                            )
                            return false
                        }
                    }
                }
                var results: [Bool] = []
                for await outcome in group {
                    results.append(outcome)
                }
                return results
            }
            let succeededCount = outcomes.filter { $0 }.count
            return RetryBatchResult(succeeded: succeededCount, failed: outcomes.count - succeededCount)
        }
    }

    private func startCaptureProcessing(_ request: QueuedCaptureRequest) {
        notifyDelegate { delegate in
            delegate.snapshotProcessingCoordinator(self, didStartCaptureFrom: request.source)
        }
        notifyProcessingStateChanged()
        Task {
            do {
                let (capturedSnapshot, screenshotData) = try await captureSnapshot()
                let result: CaptureWorkflowResult
                do {
                    result = try await captureWorkflow.runCapture(
                        capturedSnapshot: capturedSnapshot,
                        screenshotData: screenshotData
                    )
                } catch {
                    notifyDelegate { delegate in
                        delegate.snapshotProcessingCoordinator(
                            self,
                            didFailCaptureFrom: request.source,
                            stage: .workflow,
                            error: error
                        )
                    }
                    completeCaptureAndStartNextIfNeeded()
                    return
                }
                notifyDelegate { delegate in
                    delegate.snapshotProcessingCoordinator(
                        self,
                        didFinishCaptureFrom: request.source,
                        result: result
                    )
                }
            } catch {
                notifyDelegate { delegate in
                    delegate.snapshotProcessingCoordinator(
                        self,
                        didFailCaptureFrom: request.source,
                        stage: .capture,
                        error: error
                    )
                }
            }
            completeCaptureAndStartNextIfNeeded()
        }
    }

    private func completeCaptureAndStartNextIfNeeded() {
        let completion = stateQueue.sync {
            captureQueue.completeCurrentCapture()
        }
        notifyProcessingStateChanged()
        guard case .startNext(let nextRequest, _) = completion else {
            return
        }
        startCaptureProcessing(nextRequest)
    }

    private func captureSnapshot() async throws -> (CapturedSnapshot, Data?) {
        try await withCheckedThrowingContinuation { continuation in
            captureExecutionQueue.async { [captureService] in
                do {
                    continuation.resume(returning: try captureService.capture())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func retrySnapshotInBackground(_ snapshotId: UUID) async throws -> Snapshot {
        try await Task.detached(priority: .userInitiated) { [retryWorkflow] in
            try await retryWorkflow.retryFailedSnapshot(snapshotId)
        }.value
    }

    private func withRetryOperationTracking<T>(_ operation: () async throws -> T) async rethrows -> T {
        beginRetryOperation()
        do {
            let result = try await operation()
            endRetryOperation()
            return result
        } catch {
            endRetryOperation()
            throw error
        }
    }

    private func beginRetryOperation() {
        stateQueue.sync {
            activeRetryOperations += 1
        }
        notifyProcessingStateChanged()
    }

    private func endRetryOperation() {
        stateQueue.sync {
            activeRetryOperations = max(0, activeRetryOperations - 1)
        }
        notifyProcessingStateChanged()
    }

    private func notifyProcessingStateChanged() {
        notifyDelegate { delegate in
            delegate.snapshotProcessingCoordinatorDidChangeProcessingState(self)
        }
    }

    private func notifyDelegate(_ block: @MainActor @escaping (any SnapshotProcessingCoordinatorDelegate) -> Void) {
        Task { @MainActor [weak self] in
            guard let self, let delegate = self.delegate else {
                return
            }
            block(delegate)
        }
    }

    private static func defaultMaxConcurrentCaptureProcesses() -> Int {
        let config = DevelopmentConfig.shared
        let providerLimits = ProviderName.allCases.map { provider in
            config.providerParallelWorkLimit(for: provider)
        }
        return max(1, providerLimits.max() ?? 1)
    }
}
