import ContextGenerator
import XCTest

final class DensificationServiceTests: XCTestCase {
    func testProviderFactoryReturnsClient() {
        XCTAssertNotNil(ProviderClientFactory.make(provider: .openai))
        XCTAssertNotNil(ProviderClientFactory.make(provider: .anthropic))
        XCTAssertNotNil(ProviderClientFactory.make(provider: .gemini))
    }
}
