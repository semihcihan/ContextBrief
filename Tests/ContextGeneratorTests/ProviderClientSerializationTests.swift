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

private actor ProviderPresenceTracker {
    private var inFlightByProvider: [ProviderName: Int] = [:]
    private var maxCombinedInFlight = 0

    func beginCall(provider: ProviderName) {
        inFlightByProvider[provider, default: 0] += 1
        maxCombinedInFlight = max(maxCombinedInFlight, inFlightByProvider.values.reduce(0, +))
    }

    func endCall(provider: ProviderName) {
        inFlightByProvider[provider] = max(0, inFlightByProvider[provider, default: 0] - 1)
    }

    func peakCombinedConcurrency() -> Int {
        maxCombinedInFlight
    }
}

final class ProviderClientSerializationTests: XCTestCase {
    func testProviderWorkLimiterRespectsConfiguredLimitPerProvider() async {
        let limiter = ProviderWorkLimiter()
        let tracker = ProviderCallConcurrencyTracker()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 6 {
                group.addTask {
                    _ = await limiter.acquire(provider: .codex, limit: 2)
                    await tracker.beginCall()
                    try? await Task.sleep(nanoseconds: 40_000_000)
                    await tracker.endCall()
                    await limiter.release(provider: .codex)
                }
            }
        }
        let peakConcurrency = await tracker.peakConcurrency()
        XCTAssertEqual(peakConcurrency, 2)
    }

    func testProviderWorkLimiterAllowsParallelWorkAcrossDifferentProviders() async {
        let limiter = ProviderWorkLimiter()
        let tracker = ProviderPresenceTracker()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = await limiter.acquire(provider: .codex, limit: 1)
                await tracker.beginCall(provider: .codex)
                try? await Task.sleep(nanoseconds: 80_000_000)
                await tracker.endCall(provider: .codex)
                await limiter.release(provider: .codex)
            }
            group.addTask {
                _ = await limiter.acquire(provider: .gemini, limit: 1)
                await tracker.beginCall(provider: .gemini)
                try? await Task.sleep(nanoseconds: 80_000_000)
                await tracker.endCall(provider: .gemini)
                await limiter.release(provider: .gemini)
            }
        }
        let peakCombinedConcurrency = await tracker.peakCombinedConcurrency()
        XCTAssertEqual(peakCombinedConcurrency, 2)
    }
}
