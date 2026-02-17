import ContextGenerator
import Foundation

struct QueuedCaptureRequest: Equatable {
    let source: String
    let capturedSnapshot: CapturedSnapshot
    let screenshotData: Data?
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

    private(set) var isCaptureInProgress = false
    private var queuedRequests: [QueuedCaptureRequest] = []

    var queuedCount: Int {
        queuedRequests.count
    }

    func requestCapture(_ request: QueuedCaptureRequest) -> RequestResult {
        if isCaptureInProgress {
            queuedRequests.append(request)
            return .queued(count: queuedRequests.count)
        }
        isCaptureInProgress = true
        return .startNow(request: request)
    }

    func markCurrentCaptureDidNotStart() {
        isCaptureInProgress = false
    }

    func completeCurrentCapture() -> CompletionResult {
        isCaptureInProgress = false
        guard !queuedRequests.isEmpty else {
            return .idle
        }
        let nextRequest = queuedRequests.removeFirst()
        isCaptureInProgress = true
        return .startNext(request: nextRequest, remainingQueued: queuedRequests.count)
    }

    @discardableResult
    func dropQueuedCapturesAfterRejectedStart() -> Int {
        isCaptureInProgress = false
        let droppedCount = queuedRequests.count
        queuedRequests.removeAll()
        return droppedCount
    }
}
