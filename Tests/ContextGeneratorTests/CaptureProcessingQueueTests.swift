@testable import ContextBriefApp
import XCTest

final class CaptureProcessingQueueTests: XCTestCase {
    func testQueuedRequestsAreProcessedInOrder() {
        let queue = CaptureProcessingQueue()

        XCTAssertEqual(queue.requestCapture(source: "menu"), .startNow(source: "menu"))
        XCTAssertEqual(queue.requestCapture(source: "hotkey"), .queued(count: 1))
        XCTAssertEqual(queue.requestCapture(source: "menu"), .queued(count: 2))
        XCTAssertTrue(queue.isCaptureInProgress)
        XCTAssertEqual(queue.queuedCount, 2)

        XCTAssertEqual(
            queue.completeCurrentCapture(),
            .startNext(source: "hotkey", remainingQueued: 1)
        )
        XCTAssertTrue(queue.isCaptureInProgress)

        XCTAssertEqual(
            queue.completeCurrentCapture(),
            .startNext(source: "menu", remainingQueued: 0)
        )
        XCTAssertTrue(queue.isCaptureInProgress)

        XCTAssertEqual(queue.completeCurrentCapture(), .idle)
        XCTAssertFalse(queue.isCaptureInProgress)
        XCTAssertEqual(queue.queuedCount, 0)
    }

    func testRejectedQueuedStartDropsPendingCapturesAndResetsState() {
        let queue = CaptureProcessingQueue()

        _ = queue.requestCapture(source: "menu")
        _ = queue.requestCapture(source: "hotkey")
        _ = queue.requestCapture(source: "shortcut")

        XCTAssertEqual(
            queue.completeCurrentCapture(),
            .startNext(source: "hotkey", remainingQueued: 1)
        )
        XCTAssertTrue(queue.isCaptureInProgress)

        let droppedCount = queue.dropQueuedCapturesAfterRejectedStart()
        XCTAssertEqual(droppedCount, 1)
        XCTAssertFalse(queue.isCaptureInProgress)
        XCTAssertEqual(queue.queuedCount, 0)

        XCTAssertEqual(queue.requestCapture(source: "menu"), .startNow(source: "menu"))
        XCTAssertTrue(queue.isCaptureInProgress)
    }

    func testInitialStartFailureReleasesInProgressState() {
        let queue = CaptureProcessingQueue()

        XCTAssertEqual(queue.requestCapture(source: "menu"), .startNow(source: "menu"))
        XCTAssertTrue(queue.isCaptureInProgress)

        queue.markCurrentCaptureDidNotStart()

        XCTAssertFalse(queue.isCaptureInProgress)
        XCTAssertEqual(queue.queuedCount, 0)
    }
}
