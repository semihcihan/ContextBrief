import ContextGenerator
import XCTest

private final class RetrySuccessDensifier: Densifying {
    func densify(snapshot: CapturedSnapshot, provider: ProviderName, model: String, apiKey: String) async throws -> (content: String, title: String?) {
        XCTAssertEqual(provider, .codex)
        return ("dense-after-manual-retry", nil)
    }
}

private final class RetryFailureDensifier: Densifying {
    func densify(snapshot: CapturedSnapshot, provider: ProviderName, model: String, apiKey: String) async throws -> (content: String, title: String?) {
        XCTAssertEqual(provider, .codex)
        throw AppError.providerRequestTransientFailure("manual retry failed")
    }
}

private final class RetryMockKeychain: KeychainServicing {
    private var values: [String: String] = [:]

    func set(_ value: String, for key: String) throws {
        values[key] = value
    }

    func get(_ key: String) throws -> String? {
        values[key]
    }

    func delete(_ key: String) throws {
        values.removeValue(forKey: key)
    }
}

final class SnapshotRetryWorkflowTests: XCTestCase {
    func testRetryFailedSnapshotMarksItReadyOnSuccess() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        let keychain = RetryMockKeychain()

        _ = try manager.createNewContext(title: "Current")
        let failed = try manager.appendSnapshot(
            rawCapture: CapturedSnapshot(
                sourceType: .desktopApp,
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                windowTitle: "Editor",
                captureMethod: .hybrid,
                accessibilityText: "raw",
                ocrText: "",
                combinedText: "raw",
                diagnostics: CaptureDiagnostics(
                    accessibilityLineCount: 1,
                    ocrLineCount: 0,
                    processingDurationMs: 30,
                    usedFallbackOCR: false
                )
            ),
            denseContent: "",
            provider: .codex,
            model: "gpt-5-nano",
            status: .failed,
            failureMessage: "initial failure",
            retryCount: 1,
            lastAttemptAt: Date()
        )

        let workflow = SnapshotRetryWorkflow(
            repository: repo,
            densificationService: RetrySuccessDensifier(),
            keychain: keychain
        )

        let retried = try await workflow.retryFailedSnapshot(failed.id)

        XCTAssertEqual(retried.status, .ready)
        XCTAssertEqual(retried.denseContent, "dense-after-manual-retry")
        XCTAssertEqual(retried.retryCount, 2)
        XCTAssertNil(retried.failureMessage)
        XCTAssertNotNil(retried.lastAttemptAt)
    }

    func testRetryFailedSnapshotKeepsFailureStateWhenRetryFails() async throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)
        let manager = ContextSessionManager(repository: repo)
        let keychain = RetryMockKeychain()

        _ = try manager.createNewContext(title: "Current")
        let failed = try manager.appendSnapshot(
            rawCapture: CapturedSnapshot(
                sourceType: .desktopApp,
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                windowTitle: "Editor",
                captureMethod: .hybrid,
                accessibilityText: "raw",
                ocrText: "",
                combinedText: "raw",
                diagnostics: CaptureDiagnostics(
                    accessibilityLineCount: 1,
                    ocrLineCount: 0,
                    processingDurationMs: 30,
                    usedFallbackOCR: false
                )
            ),
            denseContent: "",
            provider: .codex,
            model: "gpt-5-nano",
            status: .failed,
            failureMessage: "initial failure",
            retryCount: 0,
            lastAttemptAt: Date()
        )

        let workflow = SnapshotRetryWorkflow(
            repository: repo,
            densificationService: RetryFailureDensifier(),
            keychain: keychain
        )

        do {
            _ = try await workflow.retryFailedSnapshot(failed.id)
            XCTFail("Expected retry to fail")
        } catch {}

        let updated = try repo.snapshot(id: failed.id)
        XCTAssertEqual(updated?.status, .failed)
        XCTAssertEqual(updated?.retryCount, 1)
        XCTAssertEqual(updated?.failureMessage, "manual retry failed")
        XCTAssertNotNil(updated?.lastAttemptAt)
    }
}
