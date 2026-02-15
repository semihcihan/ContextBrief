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
}
