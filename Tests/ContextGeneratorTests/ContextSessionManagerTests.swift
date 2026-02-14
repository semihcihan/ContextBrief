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
}
