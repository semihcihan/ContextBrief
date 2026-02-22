import ContextGenerator
import XCTest

private final class RecordingProviderClient: ProviderClient {
    let provider: ProviderName = .codex
    var densificationRequests: [DensificationRequest] = []
    var nextResponse: String

    init(nextResponse: String) {
        self.nextResponse = nextResponse
    }

    func requestText(request: ProviderTextRequest, model: String) async throws -> String {
        nextResponse
    }

    func requestDensification(request: DensificationRequest, model: String) async throws -> DensificationResult {
        densificationRequests.append(request)
        return DensificationResult(content: nextResponse, title: nil)
    }
}

final class DensificationServiceTests: XCTestCase {
    func testProviderFactoryReturnsClient() {
        XCTAssertNotNil(ProviderClientFactory.make(provider: .codex))
        XCTAssertNotNil(ProviderClientFactory.make(provider: .claude))
        XCTAssertNotNil(ProviderClientFactory.make(provider: .gemini))
    }

    func testDensifyUsesFilteredCombinedTextWhenAvailable() async throws {
        let client = RecordingProviderClient(nextResponse: "dense")
        let service = DensificationService(
            clientFactory: { _, _ in
                client
            }
        )
        let snapshot = makeSnapshot(
            combinedText: "baseline content",
            filteredCombinedText: "filtered content"
        )

        _ = try await service.densify(
            snapshot: snapshot,
            provider: .codex,
            model: "test-model"
        )

        XCTAssertEqual(client.densificationRequests.count, 1)
        XCTAssertEqual(client.densificationRequests.first?.inputText, "filtered content")
    }

    func testDensifyFallsBackToBaselineWhenFilteredCombinedTextIsBlank() async throws {
        let client = RecordingProviderClient(nextResponse: "dense")
        let service = DensificationService(
            clientFactory: { _, _ in
                client
            }
        )
        let snapshot = makeSnapshot(
            combinedText: "baseline content",
            filteredCombinedText: "   "
        )

        _ = try await service.densify(
            snapshot: snapshot,
            provider: .codex,
            model: "test-model"
        )

        XCTAssertEqual(client.densificationRequests.count, 1)
        XCTAssertEqual(client.densificationRequests.first?.inputText, "baseline content")
    }

    func testDensifyReturnsChosenInputWhenProviderReturnsEmptyString() async throws {
        let client = RecordingProviderClient(nextResponse: "")
        let service = DensificationService(
            clientFactory: { _, _ in
                client
            }
        )
        let snapshot = makeSnapshot(
            combinedText: "baseline content",
            filteredCombinedText: "filtered content"
        )

        let result = try await service.densify(
            snapshot: snapshot,
            provider: .codex,
            model: "test-model"
        )

        XCTAssertEqual(result.content, "filtered content")
        XCTAssertNil(result.title)
    }

    private func makeSnapshot(combinedText: String, filteredCombinedText: String?) -> CapturedSnapshot {
        CapturedSnapshot(
            sourceType: .browserTab,
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            windowTitle: "Example",
            captureMethod: .hybrid,
            accessibilityText: combinedText,
            ocrText: "",
            combinedText: combinedText,
            filteredCombinedText: filteredCombinedText,
            diagnostics: CaptureDiagnostics(
                accessibilityLineCount: 1,
                ocrLineCount: 0,
                processingDurationMs: 10,
                usedFallbackOCR: false
            )
        )
    }
}
