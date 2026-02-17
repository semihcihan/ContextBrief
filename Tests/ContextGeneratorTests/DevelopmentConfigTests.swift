import ContextGenerator
import Foundation
import XCTest

final class DevelopmentConfigTests: XCTestCase {
    func testDefaultsWhenPlistMissing() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.plist")
        let config = DevelopmentConfig(plistURL: missingURL, appleFoundationAvailableOverride: false)

        XCTAssertFalse(config.enableLocalDebugProvider)
        XCTAssertFalse(config.enableAppleFoundationForTitleGeneration)
        XCTAssertFalse(config.enableAppleFoundationForDensification)
        XCTAssertEqual(config.thirdPartyContextTitleRefreshEvery, 3)
        XCTAssertEqual(config.appleContextTitleRefreshEvery, 6)
        XCTAssertEqual(config.forcedProviderFailureChance, 0)
        XCTAssertFalse(config.appleFoundationProviderEnabled)
    }

    func testLoadsValuesFromPlist() throws {
        let plistURL = try writePlist([
            "enableLocalDebugProvider": true,
            "enableAppleFoundationForTitleGeneration": true,
            "enableAppleFoundationForDensification": false,
            "thirdPartyContextTitleRefreshEvery": 5,
            "appleContextTitleRefreshEvery": 2,
            "forcedProviderFailureChance": 0.4
        ])
        let config = DevelopmentConfig(plistURL: plistURL, appleFoundationAvailableOverride: true)

        XCTAssertTrue(config.enableLocalDebugProvider)
        XCTAssertTrue(config.enableAppleFoundationForTitleGeneration)
        XCTAssertFalse(config.enableAppleFoundationForDensification)
        XCTAssertEqual(config.thirdPartyContextTitleRefreshEvery, 5)
        XCTAssertEqual(config.appleContextTitleRefreshEvery, 2)
#if DEBUG
        XCTAssertEqual(config.forcedProviderFailureChance, 0.4, accuracy: 0.0001)
#else
        XCTAssertEqual(config.forcedProviderFailureChance, 0)
#endif
    }

    func testRoutingUsesAvailabilityAndFeatureFlags() {
        let configUnavailable = DevelopmentConfig(
            enableAppleFoundationForTitleGeneration: true,
            enableAppleFoundationForDensification: true,
            appleFoundationAvailableOverride: false
        )
        XCTAssertEqual(configUnavailable.providerForTitleGeneration(selectedProvider: .openai), .openai)
        XCTAssertEqual(configUnavailable.providerForDensification(selectedProvider: .gemini), .gemini)

        let configAvailable = DevelopmentConfig(
            enableAppleFoundationForTitleGeneration: true,
            enableAppleFoundationForDensification: false,
            thirdPartyContextTitleRefreshEvery: 4,
            appleContextTitleRefreshEvery: 2,
            appleFoundationAvailableOverride: true
        )
        XCTAssertEqual(configAvailable.providerForTitleGeneration(selectedProvider: .openai), .apple)
        XCTAssertEqual(configAvailable.providerForDensification(selectedProvider: .openai), .openai)
        XCTAssertTrue(configAvailable.appleFoundationProviderEnabled)
        XCTAssertEqual(configAvailable.contextTitleRefreshEvery(for: .openai), 4)
        XCTAssertEqual(configAvailable.contextTitleRefreshEvery(for: .apple), 2)
    }

    func testRefreshIntervalsAreClampedToMinimumOne() {
        let config = DevelopmentConfig(
            thirdPartyContextTitleRefreshEvery: 0,
            appleContextTitleRefreshEvery: -2
        )
        XCTAssertEqual(config.thirdPartyContextTitleRefreshEvery, 1)
        XCTAssertEqual(config.appleContextTitleRefreshEvery, 1)
    }

    func testForcedProviderFailureChanceIsClamped() {
        let lowChance = DevelopmentConfig(forcedProviderFailureChance: -0.4)
        let highChance = DevelopmentConfig(forcedProviderFailureChance: 1.4)

#if DEBUG
        XCTAssertEqual(lowChance.forcedProviderFailureChance, 0)
        XCTAssertEqual(highChance.forcedProviderFailureChance, 1)
#else
        XCTAssertEqual(lowChance.forcedProviderFailureChance, 0)
        XCTAssertEqual(highChance.forcedProviderFailureChance, 0)
#endif
    }

    func testLocalDebugFlagCanDisableCredentialRequirements() {
        let config = DevelopmentConfig(
            enableLocalDebugProvider: true
        )

#if DEBUG
        XCTAssertFalse(config.requiresCredentials(for: .openai))
        XCTAssertFalse(config.requiresCredentials(for: .gemini))
#else
        XCTAssertTrue(config.requiresCredentials(for: .openai))
        XCTAssertTrue(config.requiresCredentials(for: .gemini))
#endif
        XCTAssertFalse(config.requiresCredentials(for: .apple))
    }

    private func writePlist(_ dictionary: [String: Any]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DevelopmentConfigTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("config.plist")
        let wrote = (dictionary as NSDictionary).write(to: url, atomically: true)
        XCTAssertTrue(wrote)
        return url
    }
}
