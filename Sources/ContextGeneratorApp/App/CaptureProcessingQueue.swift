import Foundation

final class CaptureProcessingQueue {
    enum RequestResult: Equatable {
        case startNow(source: String)
        case queued(count: Int)
    }

    enum CompletionResult: Equatable {
        case idle
        case startNext(source: String, remainingQueued: Int)
    }

    private(set) var isCaptureInProgress = false
    private var queuedSources: [String] = []

    var queuedCount: Int {
        queuedSources.count
    }

    func requestCapture(source: String) -> RequestResult {
        if isCaptureInProgress {
            queuedSources.append(source)
            return .queued(count: queuedSources.count)
        }
        isCaptureInProgress = true
        return .startNow(source: source)
    }

    func markCurrentCaptureDidNotStart() {
        isCaptureInProgress = false
    }

    func completeCurrentCapture() -> CompletionResult {
        isCaptureInProgress = false
        guard !queuedSources.isEmpty else {
            return .idle
        }
        let nextSource = queuedSources.removeFirst()
        isCaptureInProgress = true
        return .startNext(source: nextSource, remainingQueued: queuedSources.count)
    }

    @discardableResult
    func dropQueuedCapturesAfterRejectedStart() -> Int {
        isCaptureInProgress = false
        let droppedCount = queuedSources.count
        queuedSources.removeAll()
        return droppedCount
    }
}
