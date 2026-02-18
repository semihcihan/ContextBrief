import ContextGenerator
import XCTest

private final class MockDensifier: Densifying {
    func densify(snapshot: CapturedSnapshot, provider: ProviderName, model: String, apiKey: String) async throws -> String {
        "dense-output"
    }
}

private final class FlakyDensifier: Densifying {
    private(set) var calls = 0

    func densify(snapshot: CapturedSnapshot, provider: ProviderName, model: String, apiKey: String) async throws -> String {
        calls += 1
        if calls == 1 {
            throw AppError.providerRequestFailed("temporary provider error")
        }
        return "dense-after-retry"
    }
}

private final class AlwaysFailingDensifier: Densifying {
    func densify(snapshot: CapturedSnapshot, provider: ProviderName, model: String, apiKey: String) async throws -> String {
        throw AppError.providerRequestFailed("provider unavailable")
    }
}

private final class MockKeychain: KeychainServicing {
    private var map: [String: String] = [:]
    func set(_ value: String, for key: String) throws {
        map[key] = value
    }

    func get(_ key: String) throws -> String? {
        map[key]
    }

    func delete(_ key: String) throws {
        map.removeValue(forKey: key)
    }
}

final class CaptureWorkflowTests: XCTestCase {
    func testWorkflowAppendsDenseSnapshot() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        let keychain = MockKeychain()
        let workflow = CaptureWorkflow(
            sessionManager: manager,
            repository: repo,
            densificationService: MockDensifier(),
            keychain: keychain
        )

        var state = try repo.appState()
        state.onboardingCompleted = true
        state.selectedProvider = .openai
        state.selectedModel = "demo-model"
        try repo.saveAppState(state)
        try keychain.set("secret", for: "api.openai")

        _ = try manager.createNewContext(title: "Current")
        let result = try await workflow.runCapture(
            capturedSnapshot: makeCapturedSnapshot(),
            screenshotData: nil
        )
        XCTAssertEqual(result.snapshot.denseContent, "dense-output")
        XCTAssertEqual(try repo.snapshots(in: result.context.id).count, 1)
    }

    func testWorkflowRetriesOnceBeforePersistingReadySnapshot() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        let keychain = MockKeychain()
        let densifier = FlakyDensifier()
        let workflow = CaptureWorkflow(
            sessionManager: manager,
            repository: repo,
            densificationService: densifier,
            keychain: keychain
        )

        var state = try repo.appState()
        state.onboardingCompleted = true
        state.selectedProvider = .openai
        state.selectedModel = "demo-model"
        try repo.saveAppState(state)
        try keychain.set("secret", for: "api.openai")
        _ = try manager.createNewContext(title: "Current")

        let result = try await workflow.runCapture(
            capturedSnapshot: makeCapturedSnapshot(),
            screenshotData: nil
        )

        XCTAssertEqual(densifier.calls, 2)
        XCTAssertEqual(result.snapshot.status, .ready)
        XCTAssertEqual(result.snapshot.retryCount, 1)
        XCTAssertEqual(result.snapshot.denseContent, "dense-after-retry")
    }

    func testWorkflowPersistsFailedSnapshotWhenDensificationStillFails() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        let keychain = MockKeychain()
        let workflow = CaptureWorkflow(
            sessionManager: manager,
            repository: repo,
            densificationService: AlwaysFailingDensifier(),
            keychain: keychain
        )

        var state = try repo.appState()
        state.onboardingCompleted = true
        state.selectedProvider = .openai
        state.selectedModel = "demo-model"
        try repo.saveAppState(state)
        try keychain.set("secret", for: "api.openai")
        _ = try manager.createNewContext(title: "Current")

        let result = try await workflow.runCapture(
            capturedSnapshot: makeCapturedSnapshot(),
            screenshotData: nil
        )
        let storedSnapshots = try repo.snapshots(in: result.context.id)

        XCTAssertEqual(storedSnapshots.count, 1)
        XCTAssertEqual(result.snapshot.status, .failed)
        XCTAssertEqual(result.snapshot.retryCount, 1)
        XCTAssertEqual(result.snapshot.denseContent, "")
        XCTAssertEqual(result.snapshot.failureMessage, "provider unavailable")
    }

    private func makeCapturedSnapshot() -> CapturedSnapshot {
        CapturedSnapshot(
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
                processingDurationMs: 80,
                usedFallbackOCR: true
            )
        )
    }
}
