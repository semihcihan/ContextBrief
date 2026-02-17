@testable import ContextBriefApp
import ContextGenerator
import XCTest

final class CaptureProcessingQueueTests: XCTestCase {
    func testQueuedRequestsAreProcessedInOrder() {
        let queue = CaptureProcessingQueue()
        let first = makeRequest(source: "menu")
        let second = makeRequest(source: "hotkey")
        let third = makeRequest(source: "menu")

        XCTAssertEqual(queue.requestCapture(first), .startNow(request: first))
        XCTAssertEqual(queue.requestCapture(second), .queued(count: 1))
        XCTAssertEqual(queue.requestCapture(third), .queued(count: 2))
        XCTAssertTrue(queue.isCaptureInProgress)
        XCTAssertEqual(queue.queuedCount, 2)

        XCTAssertEqual(
            queue.completeCurrentCapture(),
            .startNext(request: second, remainingQueued: 1)
        )
        XCTAssertTrue(queue.isCaptureInProgress)

        XCTAssertEqual(
            queue.completeCurrentCapture(),
            .startNext(request: third, remainingQueued: 0)
        )
        XCTAssertTrue(queue.isCaptureInProgress)

        XCTAssertEqual(queue.completeCurrentCapture(), .idle)
        XCTAssertFalse(queue.isCaptureInProgress)
        XCTAssertEqual(queue.queuedCount, 0)
    }

    func testRejectedQueuedStartDropsPendingCapturesAndResetsState() {
        let queue = CaptureProcessingQueue()
        let first = makeRequest(source: "menu")
        let second = makeRequest(source: "hotkey")
        let third = makeRequest(source: "shortcut")

        _ = queue.requestCapture(first)
        _ = queue.requestCapture(second)
        _ = queue.requestCapture(third)

        XCTAssertEqual(
            queue.completeCurrentCapture(),
            .startNext(request: second, remainingQueued: 1)
        )
        XCTAssertTrue(queue.isCaptureInProgress)

        let droppedCount = queue.dropQueuedCapturesAfterRejectedStart()
        XCTAssertEqual(droppedCount, 1)
        XCTAssertFalse(queue.isCaptureInProgress)
        XCTAssertEqual(queue.queuedCount, 0)

        XCTAssertEqual(queue.requestCapture(first), .startNow(request: first))
        XCTAssertTrue(queue.isCaptureInProgress)
    }

    func testInitialStartFailureReleasesInProgressState() {
        let queue = CaptureProcessingQueue()
        let first = makeRequest(source: "menu")

        XCTAssertEqual(queue.requestCapture(first), .startNow(request: first))
        XCTAssertTrue(queue.isCaptureInProgress)

        queue.markCurrentCaptureDidNotStart()

        XCTAssertFalse(queue.isCaptureInProgress)
        XCTAssertEqual(queue.queuedCount, 0)
    }

    private func makeRequest(source: String) -> QueuedCaptureRequest {
        QueuedCaptureRequest(
            source: source,
            capturedSnapshot: CapturedSnapshot(
                sourceType: .desktopApp,
                appName: "Terminal",
                bundleIdentifier: "com.apple.Terminal",
                windowTitle: "zsh",
                captureMethod: .hybrid,
                accessibilityText: "access",
                ocrText: "ocr",
                combinedText: "access\no cr",
                diagnostics: CaptureDiagnostics(
                    accessibilityLineCount: 1,
                    ocrLineCount: 1,
                    processingDurationMs: 100,
                    usedFallbackOCR: true
                )
            ),
            screenshotData: nil
        )
    }
}
