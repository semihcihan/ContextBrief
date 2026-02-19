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
        XCTAssertEqual(config.thirdPartyContextTitleRefreshEvery, 3)
        XCTAssertEqual(config.appleContextTitleRefreshEvery, 6)
        XCTAssertEqual(config.forcedProviderFailureChance, 0)
        XCTAssertEqual(config.providerParallelWorkLimitDefault, 10)
        XCTAssertEqual(config.providerParallelWorkLimit(for: .apple), 10)
        XCTAssertEqual(config.providerParallelWorkLimit(for: .openai), 10)
        XCTAssertNil(config.snapshotInactivityPromptMinutes)
        XCTAssertFalse(config.appleFoundationProviderEnabled)
    }

    func testLoadsValuesFromPlist() throws {
        let plistURL = try writePlist([
            "enableLocalDebugProvider": true,
            "thirdPartyContextTitleRefreshEvery": 5,
            "appleContextTitleRefreshEvery": 2,
            "forcedProviderFailureChance": 0.4,
            "providerParallelWorkLimitDefault": 8,
            "providerParallelWorkLimitApple": 3,
            "providerParallelWorkLimitOpenAI": 12,
            "snapshotInactivityPromptMinutes": 30
        ])
        let config = DevelopmentConfig(plistURL: plistURL, appleFoundationAvailableOverride: true)

        XCTAssertTrue(config.enableLocalDebugProvider)
        XCTAssertEqual(config.thirdPartyContextTitleRefreshEvery, 5)
        XCTAssertEqual(config.appleContextTitleRefreshEvery, 2)
#if DEBUG
        XCTAssertEqual(config.forcedProviderFailureChance, 0.4, accuracy: 0.0001)
#else
        XCTAssertEqual(config.forcedProviderFailureChance, 0)
#endif
        XCTAssertEqual(config.providerParallelWorkLimitDefault, 8)
        XCTAssertEqual(config.providerParallelWorkLimit(for: .apple), 3)
        XCTAssertEqual(config.providerParallelWorkLimit(for: .openai), 12)
        XCTAssertEqual(config.providerParallelWorkLimit(for: .anthropic), 8)
        XCTAssertEqual(config.snapshotInactivityPromptMinutes, 30)
    }

    func testRoutingUsesSelectedProviderWithoutImplicitAppleOverrides() {
        let configUnavailable = DevelopmentConfig(
            appleFoundationAvailableOverride: false
        )
        XCTAssertEqual(configUnavailable.providerForTitleGeneration(selectedProvider: .apple), .apple)
        XCTAssertEqual(configUnavailable.providerForDensification(selectedProvider: .gemini), .gemini)
        XCTAssertFalse(configUnavailable.appleFoundationProviderEnabled)

        let configAvailable = DevelopmentConfig(
            thirdPartyContextTitleRefreshEvery: 4,
            appleContextTitleRefreshEvery: 2,
            appleFoundationAvailableOverride: true
        )
        XCTAssertEqual(configAvailable.providerForTitleGeneration(selectedProvider: .openai), .openai)
        XCTAssertEqual(configAvailable.providerForDensification(selectedProvider: .apple), .apple)
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

    func testProviderParallelLimitFallbackAndClamping() {
        let config = DevelopmentConfig(
            providerParallelWorkLimitDefault: 0,
            providerParallelWorkLimitApple: -4,
            providerParallelWorkLimitOpenAI: 0,
            providerParallelWorkLimitAnthropic: 6
        )
        XCTAssertEqual(config.providerParallelWorkLimitDefault, 1)
        XCTAssertEqual(config.providerParallelWorkLimit(for: .apple), 1)
        XCTAssertEqual(config.providerParallelWorkLimit(for: .openai), 1)
        XCTAssertEqual(config.providerParallelWorkLimit(for: .anthropic), 6)
        XCTAssertEqual(config.providerParallelWorkLimit(for: .gemini), 1)
    }

    func testSnapshotInactivityPromptMinutesIsOptionalAndClamped() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.plist")
        let missingValueConfig = DevelopmentConfig(plistURL: missingURL)
        XCTAssertNil(missingValueConfig.snapshotInactivityPromptMinutes)

        let clampedConfig = DevelopmentConfig(
            snapshotInactivityPromptMinutes: 0,
            plistURL: missingURL
        )
        XCTAssertEqual(clampedConfig.snapshotInactivityPromptMinutes, 1)
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
