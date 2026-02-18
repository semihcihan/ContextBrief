@testable import ContextGenerator
import XCTest

private actor ProviderCallConcurrencyTracker {
    private var inFlightCount = 0
    private var maxInFlightCount = 0

    func beginCall() {
        inFlightCount += 1
        maxInFlightCount = max(maxInFlightCount, inFlightCount)
    }

    func endCall() {
        inFlightCount = max(0, inFlightCount - 1)
    }

    func peakConcurrency() -> Int {
        maxInFlightCount
    }
}

private struct SlowRecordingProviderClient: ProviderClient {
    let provider: ProviderName
    let tracker: ProviderCallConcurrencyTracker
    let delayNanoseconds: UInt64

    func requestText(request: ProviderTextRequest, apiKey: String, model: String) async throws -> String {
        await tracker.beginCall()
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        await tracker.endCall()
        return "ok"
    }

    func densify(request: DensificationRequest, apiKey: String, model: String) async throws -> String {
        await tracker.beginCall()
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        await tracker.endCall()
        return "ok"
    }
}

final class ProviderClientSerializationTests: XCTestCase {
    func testSerializeProviderCallsEnabledOnlyForApple() {
        XCTAssertTrue(ProviderName.apple.serializeProviderCalls)
        XCTAssertFalse(ProviderName.openai.serializeProviderCalls)
        XCTAssertFalse(ProviderName.anthropic.serializeProviderCalls)
        XCTAssertFalse(ProviderName.gemini.serializeProviderCalls)
    }

    func testFactoryWrapsOnlySerializedProviders() {
        XCTAssertTrue(ProviderClientFactory.make(provider: .apple) is SerializedProviderClient)
        XCTAssertFalse(ProviderClientFactory.make(provider: .openai) is SerializedProviderClient)
        XCTAssertFalse(ProviderClientFactory.make(provider: .anthropic) is SerializedProviderClient)
        XCTAssertFalse(ProviderClientFactory.make(provider: .gemini) is SerializedProviderClient)
    }

    func testSerializedProviderClientSerializesConcurrentRequestTextCalls() async throws {
        let tracker = ProviderCallConcurrencyTracker()
        let wrapped = SlowRecordingProviderClient(
            provider: .apple,
            tracker: tracker,
            delayNanoseconds: 80_000_000
        )
        let client = SerializedProviderClient(provider: .apple, wrapped: wrapped)

        async let first = client.requestText(
            request: ProviderTextRequest(prompt: "first"),
            apiKey: "",
            model: "apple"
        )
        async let second = client.requestText(
            request: ProviderTextRequest(prompt: "second"),
            apiKey: "",
            model: "apple"
        )

        _ = try await (first, second)

        let peakConcurrency = await tracker.peakConcurrency()
        XCTAssertEqual(peakConcurrency, 1)
    }

    func testSerializedProviderClientSerializesAcrossRequestAndDensifyCalls() async throws {
        let tracker = ProviderCallConcurrencyTracker()
        let wrapped = SlowRecordingProviderClient(
            provider: .apple,
            tracker: tracker,
            delayNanoseconds: 80_000_000
        )
        let client = SerializedProviderClient(provider: .apple, wrapped: wrapped)

        async let textCall = client.requestText(
            request: ProviderTextRequest(prompt: "title"),
            apiKey: "",
            model: "apple"
        )
        async let densifyCall = client.densify(
            request: DensificationRequest(
                inputText: "dense",
                appName: "App",
                windowTitle: "Window"
            ),
            apiKey: "",
            model: "apple"
        )

        _ = try await (textCall, densifyCall)

        let peakConcurrency = await tracker.peakConcurrency()
        XCTAssertEqual(peakConcurrency, 1)
    }
}
