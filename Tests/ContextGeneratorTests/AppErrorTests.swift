import ContextGenerator
import XCTest

final class AppErrorTests: XCTestCase {
    func testRetryableProviderFailuresAreMarkedRetryable() {
        XCTAssertTrue(AppError.providerRequestTransientFailure("temporary").isRetryableProviderFailure)
        XCTAssertTrue(
            AppError.providerRequestTimedOut(provider: .codex, timeoutSeconds: 60).isRetryableProviderFailure
        )
    }

    func testNonRetryableProviderFailuresAreMarkedNonRetryable() {
        XCTAssertFalse(AppError.providerRequestRejected("invalid model").isRetryableProviderFailure)
        XCTAssertFalse(
            AppError.providerModelUnavailable(
                provider: .gemini,
                model: "gemini-3-flash-preview",
                suggestions: ["gemini-2.5-flash"]
            ).isRetryableProviderFailure
        )
    }
}
