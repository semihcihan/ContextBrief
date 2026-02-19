import ContextGenerator
import Foundation

struct QueuedCaptureRequest: Equatable {
    let source: String
}

final class CaptureProcessingQueue {
    enum RequestResult: Equatable {
        case startNow(request: QueuedCaptureRequest)
        case queued(count: Int)
    }

    enum CompletionResult: Equatable {
        case idle
        case startNext(request: QueuedCaptureRequest, remainingQueued: Int)
    }

    private let maxConcurrentCaptures: Int
    private(set) var activeCaptureCount = 0
    private var queuedRequests: [QueuedCaptureRequest] = []

    init(maxConcurrentCaptures: Int = 1) {
        self.maxConcurrentCaptures = max(1, maxConcurrentCaptures)
    }

    var isCaptureInProgress: Bool {
        activeCaptureCount > 0
    }

    var queuedCount: Int {
        queuedRequests.count
    }

    func requestCapture(_ request: QueuedCaptureRequest) -> RequestResult {
        if activeCaptureCount >= maxConcurrentCaptures {
            queuedRequests.append(request)
            return .queued(count: queuedRequests.count)
        }
        activeCaptureCount += 1
        return .startNow(request: request)
    }

    func markCurrentCaptureDidNotStart() {
        activeCaptureCount = max(0, activeCaptureCount - 1)
    }

    func completeCurrentCapture() -> CompletionResult {
        activeCaptureCount = max(0, activeCaptureCount - 1)
        guard activeCaptureCount < maxConcurrentCaptures, !queuedRequests.isEmpty else {
            return .idle
        }
        let nextRequest = queuedRequests.removeFirst()
        activeCaptureCount += 1
        return .startNext(request: nextRequest, remainingQueued: queuedRequests.count)
    }

    @discardableResult
    func dropQueuedCapturesAfterRejectedStart() -> Int {
        activeCaptureCount = max(0, activeCaptureCount - 1)
        let droppedCount = queuedRequests.count
        queuedRequests.removeAll()
        return droppedCount
    }
}
