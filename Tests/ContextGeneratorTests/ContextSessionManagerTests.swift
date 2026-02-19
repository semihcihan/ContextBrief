import ContextGenerator
import XCTest

final class ContextSessionManagerTests: XCTestCase {
    func testCreateContextAndSetCurrent() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)

        let context = try manager.createNewContext(title: "Feature A")
        XCTAssertEqual(context.title, "Feature A")

        let current = try manager.currentContext()
        XCTAssertEqual(current.id, context.id)
    }

    func testUndoLastCapture() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        _ = try manager.createNewContext(title: "Context")

        let capture = CapturedSnapshot(
            sourceType: .desktopApp,
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            windowTitle: "Notes",
            captureMethod: .accessibility,
            accessibilityText: "abc",
            ocrText: "",
            combinedText: "abc",
            diagnostics: CaptureDiagnostics(
                accessibilityLineCount: 1,
                ocrLineCount: 0,
                processingDurationMs: 40,
                usedFallbackOCR: false
            )
        )
        _ = try manager.appendSnapshot(rawCapture: capture, denseContent: "abc", provider: nil, model: nil)
        let removed = try manager.undoLastCaptureInCurrentContext()
        XCTAssertEqual(removed.sequence, 1)
        XCTAssertEqual(try repo.snapshots(in: try manager.currentContext().id).count, 0)
        XCTAssertEqual(try manager.trashedSnapshots().count, 1)
    }

    func testPromoteLastCaptureToNewContext() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        let first = try manager.createNewContext(title: "First")

        let capture = CapturedSnapshot(
            sourceType: .desktopApp,
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            windowTitle: "Notes",
            captureMethod: .accessibility,
            accessibilityText: "abc",
            ocrText: "",
            combinedText: "abc",
            diagnostics: CaptureDiagnostics(
                accessibilityLineCount: 1,
                ocrLineCount: 0,
                processingDurationMs: 40,
                usedFallbackOCR: false
            )
        )
        _ = try manager.appendSnapshot(rawCapture: capture, denseContent: "dense", provider: nil, model: nil)

        let second = try manager.promoteLastCaptureToNewContext(title: "Second")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(try repo.snapshots(in: first.id).count, 0)
        XCTAssertEqual(try repo.snapshots(in: second.id).count, 1)
    }

    func testRestoreTrashedSnapshotToCurrentContext() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        _ = try manager.createNewContext(title: "Context")

        let capture = CapturedSnapshot(
            sourceType: .desktopApp,
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            windowTitle: "Notes",
            captureMethod: .accessibility,
            accessibilityText: "abc",
            ocrText: "",
            combinedText: "abc",
            diagnostics: CaptureDiagnostics(
                accessibilityLineCount: 1,
                ocrLineCount: 0,
                processingDurationMs: 40,
                usedFallbackOCR: false
            )
        )
        _ = try manager.appendSnapshot(rawCapture: capture, denseContent: "abc", provider: nil, model: nil)
        _ = try manager.undoLastCaptureInCurrentContext()
        let trashed = try manager.trashedSnapshots()

        XCTAssertEqual(trashed.count, 1)
        let restored = try manager.restoreTrashedSnapshotToCurrentContext(trashed[0].id)

        XCTAssertEqual(restored.sequence, 1)
        XCTAssertEqual(try manager.trashedSnapshots().count, 0)
        XCTAssertEqual(try manager.snapshotsInCurrentContext().count, 1)
    }

    func testMoveSnapshotToCurrentContext() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        let first = try manager.createNewContext(title: "First")

        let capture = CapturedSnapshot(
            sourceType: .desktopApp,
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            windowTitle: "Notes",
            captureMethod: .accessibility,
            accessibilityText: "abc",
            ocrText: "",
            combinedText: "abc",
            diagnostics: CaptureDiagnostics(
                accessibilityLineCount: 1,
                ocrLineCount: 0,
                processingDurationMs: 40,
                usedFallbackOCR: false
            )
        )
        let snapshot = try manager.appendSnapshot(rawCapture: capture, denseContent: "abc", provider: nil, model: nil)
        let second = try manager.createNewContext(title: "Second")
        try manager.setCurrentContext(second.id)
        let moved = try manager.moveSnapshotToCurrentContext(snapshot.id)

        XCTAssertEqual(moved.contextId, second.id)
        XCTAssertEqual(try repo.snapshots(in: first.id).count, 0)
        XCTAssertEqual(try repo.snapshots(in: second.id).count, 1)
    }

    func testRestoreDeletedContextPreservesName() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        let context = try manager.createNewContext(title: "Named Context")

        let capture = CapturedSnapshot(
            sourceType: .desktopApp,
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            windowTitle: "Notes",
            captureMethod: .accessibility,
            accessibilityText: "abc",
            ocrText: "",
            combinedText: "abc",
            diagnostics: CaptureDiagnostics(
                accessibilityLineCount: 1,
                ocrLineCount: 0,
                processingDurationMs: 40,
                usedFallbackOCR: false
            )
        )
        _ = try manager.appendSnapshot(rawCapture: capture, denseContent: "abc", provider: nil, model: nil)
        _ = try manager.deleteContextToTrash(context.id)

        let trashedContexts = try manager.trashedContexts()
        XCTAssertEqual(trashedContexts.count, 1)
        let restored = try manager.restoreTrashedContext(trashedContexts[0].id, setAsCurrent: true)

        XCTAssertEqual(restored.title, "Named Context")
        XCTAssertEqual(try manager.currentContext().id, restored.id)
    }

    func testDeleteTrashedSnapshotPermanentlyRemovesItem() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        _ = try manager.createNewContext(title: "Context")

        let capture = CapturedSnapshot(
            sourceType: .desktopApp,
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            windowTitle: "Notes",
            captureMethod: .accessibility,
            accessibilityText: "abc",
            ocrText: "",
            combinedText: "abc",
            diagnostics: CaptureDiagnostics(
                accessibilityLineCount: 1,
                ocrLineCount: 0,
                processingDurationMs: 40,
                usedFallbackOCR: false
            )
        )
        _ = try manager.appendSnapshot(rawCapture: capture, denseContent: "abc", provider: nil, model: nil)
        _ = try manager.undoLastCaptureInCurrentContext()
        let trashed = try manager.trashedSnapshots()

        XCTAssertEqual(trashed.count, 1)
        try manager.deleteTrashedSnapshotPermanently(trashed[0].id)
        XCTAssertTrue(try manager.trashedSnapshots().isEmpty)
    }

    func testDeleteTrashedContextPermanentlyRemovesItem() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        let context = try manager.createNewContext(title: "Named Context")

        _ = try manager.deleteContextToTrash(context.id)
        let trashed = try manager.trashedContexts()
        XCTAssertEqual(trashed.count, 1)

        try manager.deleteTrashedContextPermanently(trashed[0].id)
        XCTAssertTrue(try manager.trashedContexts().isEmpty)
    }

    func testHasFailedSnapshotsInCurrentContext() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        _ = try manager.createNewContext(title: "Context")

        let capture = CapturedSnapshot(
            sourceType: .desktopApp,
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            windowTitle: "Notes",
            captureMethod: .accessibility,
            accessibilityText: "abc",
            ocrText: "",
            combinedText: "abc",
            diagnostics: CaptureDiagnostics(
                accessibilityLineCount: 1,
                ocrLineCount: 0,
                processingDurationMs: 40,
                usedFallbackOCR: false
            )
        )

        _ = try manager.appendSnapshot(
            rawCapture: capture,
            denseContent: "dense",
            provider: .openai,
            model: "gpt-5-nano",
            status: .ready
        )
        XCTAssertFalse(try manager.hasFailedSnapshotsInCurrentContext())

        _ = try manager.appendSnapshot(
            rawCapture: capture,
            denseContent: "",
            provider: .openai,
            model: "gpt-5-nano",
            status: .failed,
            failureMessage: "provider failed",
            retryCount: 1,
            lastAttemptAt: Date()
        )
        XCTAssertTrue(try manager.hasFailedSnapshotsInCurrentContext())
    }

    func testConcurrentAppendSnapshotMaintainsUniqueSequentialOrdering() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        let context = try manager.createNewContext(title: "Parallel")
        let capture = sampleCapture()

        let group = DispatchGroup()
        let errorLock = NSLock()
        var failures: [String] = []
        for _ in 0 ..< 20 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer {
                    group.leave()
                }
                do {
                    _ = try manager.appendSnapshot(
                        rawCapture: capture,
                        denseContent: "dense",
                        provider: .openai,
                        model: "gpt-5-mini"
                    )
                } catch {
                    errorLock.lock()
                    failures.append(error.localizedDescription)
                    errorLock.unlock()
                }
            }
        }
        group.wait()

        XCTAssertTrue(failures.isEmpty)
        let snapshots = try repo.snapshots(in: context.id)
        XCTAssertEqual(snapshots.count, 20)
        XCTAssertEqual(snapshots.map(\.sequence), Array(1 ... 20))
    }

    func testAppendSnapshotUsesCurrentContextAtSaveTime() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        _ = try manager.createNewContext(title: "Old")
        let newContext = try manager.createNewContext(title: "New")
        let saved = try manager.appendSnapshot(
            rawCapture: sampleCapture(),
            denseContent: "dense",
            provider: .openai,
            model: "gpt-5-mini"
        )
        XCTAssertEqual(saved.contextId, newContext.id)
    }

    func testAppendSnapshotRecoversWhenCurrentContextWasDeleted() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        let deletedContext = try manager.createNewContext(title: "Delete Me")
        _ = try manager.deleteContextToTrash(deletedContext.id)

        let saved = try manager.appendSnapshot(
            rawCapture: sampleCapture(),
            denseContent: "dense",
            provider: .openai,
            model: "gpt-5-mini"
        )
        XCTAssertNotEqual(saved.contextId, deletedContext.id)
        XCTAssertTrue(try repo.context(id: saved.contextId) != nil)
    }

    func testShouldPromptForNewContextReturnsFalseWithoutSnapshots() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        _ = try manager.createNewContext(title: "Context")

        XCTAssertFalse(try manager.shouldPromptForNewContext(afterInactivityMinutes: 30))
    }

    func testShouldPromptForNewContextReturnsFalseForNonPositiveThreshold() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        let context = try manager.createNewContext(title: "Context")
        try repo.appendSnapshot(
            storedSnapshot(
                contextId: context.id,
                sequence: 1,
                createdAt: Date().addingTimeInterval(-3600)
            )
        )

        XCTAssertFalse(try manager.shouldPromptForNewContext(afterInactivityMinutes: 0))
        XCTAssertFalse(try manager.shouldPromptForNewContext(afterInactivityMinutes: -5))
    }

    func testShouldPromptForNewContextUsesLatestSnapshotTimestamp() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        let context = try manager.createNewContext(title: "Context")

        try repo.appendSnapshot(
            storedSnapshot(
                contextId: context.id,
                sequence: 1,
                createdAt: Date().addingTimeInterval(-31 * 60)
            )
        )
        XCTAssertTrue(try manager.shouldPromptForNewContext(afterInactivityMinutes: 30))

        try repo.appendSnapshot(
            storedSnapshot(
                contextId: context.id,
                sequence: 2,
                createdAt: Date().addingTimeInterval(-5 * 60)
            )
        )
        XCTAssertFalse(try manager.shouldPromptForNewContext(afterInactivityMinutes: 30))
    }

    private func sampleCapture() -> CapturedSnapshot {
        CapturedSnapshot(
            sourceType: .desktopApp,
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            windowTitle: "Notes",
            captureMethod: .accessibility,
            accessibilityText: "abc",
            ocrText: "",
            combinedText: "abc",
            diagnostics: CaptureDiagnostics(
                accessibilityLineCount: 1,
                ocrLineCount: 0,
                processingDurationMs: 40,
                usedFallbackOCR: false
            )
        )
    }

    private func storedSnapshot(contextId: UUID, sequence: Int, createdAt: Date) -> Snapshot {
        Snapshot(
            contextId: contextId,
            createdAt: createdAt,
            sequence: sequence,
            sourceType: .desktopApp,
            appName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            windowTitle: "Notes",
            captureMethod: .accessibility,
            rawContent: "abc",
            ocrContent: "",
            denseContent: "dense"
        )
    }
}
