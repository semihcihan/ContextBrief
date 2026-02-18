@testable import ContextGenerator
import XCTest

private actor ProviderRequestAttemptCounter {
    private var count = 0

    func next() -> Int {
        count += 1
        return count
    }

    func current() -> Int {
        count
    }
}

private struct ContextWindowMockProviderClient: ProviderClient {
    let provider: ProviderName = .openai
    let maxPromptCharacters: Int
    let contextWindowErrorMessage: String
    let counter: ProviderRequestAttemptCounter

    func requestText(request: ProviderTextRequest, apiKey: String, model: String) async throws -> String {
        let attempt = await counter.next()
        if request.prompt.count > maxPromptCharacters {
            throw AppError.providerRequestFailed(contextWindowErrorMessage)
        }
        return "dense-\(attempt)"
    }
}

private struct NonContextFailureMockProviderClient: ProviderClient {
    let provider: ProviderName = .openai
    let counter: ProviderRequestAttemptCounter
    let message: String

    func requestText(request: ProviderTextRequest, apiKey: String, model: String) async throws -> String {
        _ = await counter.next()
        throw AppError.providerRequestFailed(message)
    }
}

final class ProviderClientDensificationFallbackTests: XCTestCase {
    func testDefaultDensifyRetriesWithChunkingForCommonContextWindowErrorMessages() async throws {
        let messages = [
            "context_length_exceeded",
            "This model's maximum context length is 8192 tokens. However, your messages resulted in 9400 tokens.",
            "Prompt is too long: 12200 tokens > 8192 maximum",
            "The input token count (12200) exceeds the maximum number of tokens allowed (8192)."
        ]

        for message in messages {
            let counter = ProviderRequestAttemptCounter()
            let client = ContextWindowMockProviderClient(
                maxPromptCharacters: 4_000,
                contextWindowErrorMessage: message,
                counter: counter
            )
            let output = try await client.densify(
                request: DensificationRequest(
                    inputText: makeLargeInputText(),
                    appName: "Editor",
                    windowTitle: "Large Snapshot"
                ),
                apiKey: "test",
                model: "test-model"
            )

            XCTAssertFalse(output.isEmpty)
            let attempts = await counter.current()
            XCTAssertGreaterThan(attempts, 1)
        }
    }

    func testDefaultDensifyDoesNotRetryForNonContextWindowFailures() async {
        let counter = ProviderRequestAttemptCounter()
        let client = NonContextFailureMockProviderClient(
            counter: counter,
            message: "Rate limit exceeded: input_tokens per minute limit reached."
        )

        await XCTAssertThrowsErrorAsync(
            try await client.densify(
                request: DensificationRequest(
                    inputText: makeLargeInputText(),
                    appName: "Editor",
                    windowTitle: "Large Snapshot"
                ),
                apiKey: "test",
                model: "test-model"
            )
        ) { error in
            guard case let .providerRequestFailed(details) = error as? AppError else {
                XCTFail("Expected providerRequestFailed, got \(error)")
                return
            }
            XCTAssertEqual(details, "Rate limit exceeded: input_tokens per minute limit reached.")
        }

        let attempts = await counter.current()
        XCTAssertEqual(attempts, 1)
    }

    private func makeLargeInputText() -> String {
        Array(repeating: "Important workflow detail with high-signal context and outcomes.", count: 800)
            .joined(separator: "\n\n")
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (_ error: Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail(message(), file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
