import ContextGenerator
import XCTest

private final class MockCaptureService: ContextCapturing {
    func capture() throws -> (CapturedSnapshot, Data?) {
        (
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
            ),
            nil
        )
    }
}

private final class MockDensifier: Densifying {
    func densify(snapshot: CapturedSnapshot, provider: ProviderName, model: String, apiKey: String) async throws -> String {
        "dense-output"
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
            captureService: MockCaptureService(),
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
        let result = try await workflow.runCapture()
        XCTAssertEqual(result.snapshot.denseContent, "dense-output")
        XCTAssertEqual(try repo.snapshots(in: result.context.id).count, 1)
    }
}
