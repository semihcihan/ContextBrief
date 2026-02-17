import AppKit
import ContextGenerator
@testable import ContextBriefApp
import XCTest

private final class MockSetupPermissionService: PermissionServicing {
    func requestOnboardingPermissions() {}
    func hasAccessibilityPermission() -> Bool { true }
    func hasScreenRecordingPermission() -> Bool { true }
}

private final class MockSetupKeychain: KeychainServicing {
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

@MainActor
final class SetupViewControllerTests: XCTestCase {
    func testShowsAppleProviderWhenEnabledAndAvailable() throws {
        let (appStateService, _) = try makeAppStateService()
        let controller = makeController(
            appStateService: appStateService,
            developmentConfig: DevelopmentConfig(
                enableLocalDebugProvider: false,
                enableAppleFoundationForTitleGeneration: true,
                enableAppleFoundationForDensification: false,
                appleFoundationAvailableOverride: true
            )
        )
        controller.loadViewIfNeeded()

        XCTAssertTrue(controller.testingProviderTitles().contains("Apple Foundation"))
    }

    func testSelectingAppleDisablesModelAndAPIKeyFields() throws {
        let (appStateService, _) = try makeAppStateService()
        let controller = makeController(
            appStateService: appStateService,
            developmentConfig: DevelopmentConfig(
                enableLocalDebugProvider: false,
                enableAppleFoundationForTitleGeneration: true,
                enableAppleFoundationForDensification: false,
                appleFoundationAvailableOverride: true
            )
        )
        controller.loadViewIfNeeded()
        controller.testingSelectProvider(.apple)

        XCTAssertFalse(controller.testingModelFieldEnabled())
        XCTAssertFalse(controller.testingKeyFieldEnabled())
    }

    func testDefaultModelValueIsGpt5Nano() throws {
        let (appStateService, _) = try makeAppStateService()
        let controller = makeController(
            appStateService: appStateService,
            developmentConfig: defaultDevelopmentConfig()
        )
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.testingModelValue(), "gpt-5-nano")
    }

    func testSelectingOlderProviderRestoresSavedModelAndKey() throws {
        let (appStateService, _) = try makeAppStateService()
        try appStateService.configureProvider(provider: .openai, model: "gpt-4.1-mini", apiKey: "sk-openai")
        try appStateService.configureProvider(provider: .apple, model: "", apiKey: nil)

        let controller = makeController(
            appStateService: appStateService,
            developmentConfig: DevelopmentConfig(
                enableLocalDebugProvider: false,
                enableAppleFoundationForTitleGeneration: true,
                enableAppleFoundationForDensification: false,
                appleFoundationAvailableOverride: true
            )
        )
        controller.loadViewIfNeeded()
        controller.testingSelectProvider(.openai)

        XCTAssertEqual(controller.testingSelectedProvider(), .openai)
        XCTAssertEqual(controller.testingModelValue(), "gpt-4.1-mini")
        XCTAssertEqual(controller.testingAPIKeyValue(), "sk-openai")
        XCTAssertEqual(controller.testingInfoLabelValue(), "Ready to finish setup.")
        XCTAssertTrue(controller.testingModelFieldEnabled())
        XCTAssertTrue(controller.testingKeyFieldEnabled())
    }

    func testSelectingProviderWithoutSavedValuesUsesProviderDefaultModelAndClearsKey() throws {
        let (appStateService, _) = try makeAppStateService()
        try appStateService.configureProvider(provider: .openai, model: "gpt-4.1-mini", apiKey: "sk-openai")

        let controller = makeController(
            appStateService: appStateService,
            developmentConfig: defaultDevelopmentConfig()
        )
        controller.loadViewIfNeeded()
        controller.testingSelectProvider(.gemini)

        XCTAssertEqual(controller.testingSelectedProvider(), .gemini)
        XCTAssertEqual(controller.testingModelValue(), "gemini-flash-latest")
        XCTAssertEqual(controller.testingAPIKeyValue(), "")
        XCTAssertEqual(controller.testingInfoLabelValue(), "Enter model and API key to complete setup.")
        XCTAssertTrue(controller.testingModelFieldEnabled())
        XCTAssertTrue(controller.testingKeyFieldEnabled())
    }

    func testSelectingAnthropicWithoutSavedValuesUsesAnthropicDefaultModel() throws {
        let (appStateService, _) = try makeAppStateService()
        let controller = makeController(
            appStateService: appStateService,
            developmentConfig: defaultDevelopmentConfig()
        )
        controller.loadViewIfNeeded()
        controller.testingSelectProvider(.anthropic)

        XCTAssertEqual(controller.testingSelectedProvider(), .anthropic)
        XCTAssertEqual(controller.testingModelValue(), "claude-haiku-4-5")
        XCTAssertEqual(controller.testingAPIKeyValue(), "")
        XCTAssertEqual(controller.testingInfoLabelValue(), "Enter model and API key to complete setup.")
        XCTAssertTrue(controller.testingModelFieldEnabled())
        XCTAssertTrue(controller.testingKeyFieldEnabled())
    }

    func testCompletedSetupLoadsWithNeutralInfoAndDisabledSaveChanges() throws {
        let (appStateService, _) = try makeAppStateService()
        try appStateService.configureProvider(provider: .openai, model: "gpt-4.1-mini", apiKey: "sk-openai")
        try appStateService.markOnboardingCompleted()

        let controller = makeController(
            appStateService: appStateService,
            developmentConfig: defaultDevelopmentConfig()
        )
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.testingInfoLabelValue(), "")
        XCTAssertEqual(controller.testingFinishSetupButtonTitle(), "Save Changes")
        XCTAssertFalse(controller.testingFinishSetupButtonEnabled())
        XCTAssertTrue(controller.testingSetupCompleteBadgeVisible())
    }

    func testCompletedSetupEnablesSaveChangesWhenConfigurationBecomesDirty() throws {
        let (appStateService, _) = try makeAppStateService()
        try appStateService.configureProvider(provider: .openai, model: "gpt-4.1-mini", apiKey: "sk-openai")
        try appStateService.markOnboardingCompleted()

        let controller = makeController(
            appStateService: appStateService,
            developmentConfig: defaultDevelopmentConfig()
        )
        controller.loadViewIfNeeded()
        controller.testingSetModelValue("gpt-4.1")

        XCTAssertEqual(controller.testingFinishSetupButtonTitle(), "Save Changes")
        XCTAssertTrue(controller.testingFinishSetupButtonEnabled())
        XCTAssertFalse(controller.testingSetupCompleteBadgeVisible())
    }

    func testIncompleteOnboardingUsesFinishSetupAndActionableInfo() throws {
        let (appStateService, _) = try makeAppStateService()
        try appStateService.configureProvider(provider: .openai, model: "gpt-4.1-mini", apiKey: "sk-openai")

        let controller = makeController(
            appStateService: appStateService,
            developmentConfig: defaultDevelopmentConfig()
        )
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.testingInfoLabelValue(), "Ready to finish setup.")
        XCTAssertEqual(controller.testingFinishSetupButtonTitle(), "Finish Setup")
        XCTAssertTrue(controller.testingFinishSetupButtonEnabled())
        XCTAssertFalse(controller.testingSetupCompleteBadgeVisible())
    }

    private func makeAppStateService() throws -> (AppStateService, ContextRepository) {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SetupViewControllerTests-\(UUID().uuidString)", isDirectory: true)
        let repository = ContextRepository(rootURL: rootURL)
        let keychain = MockSetupKeychain()
        let appStateService = AppStateService(repository: repository, keychain: keychain)
        return (appStateService, repository)
    }

    private func makeController(
        appStateService: AppStateService,
        developmentConfig: DevelopmentConfig
    ) -> SetupViewController {
        SetupViewController(
            permissionService: MockSetupPermissionService(),
            appStateService: appStateService,
            developmentConfig: developmentConfig,
            onComplete: {}
        )
    }

    private func defaultDevelopmentConfig() -> DevelopmentConfig {
        DevelopmentConfig(
            enableLocalDebugProvider: false
        )
    }
}
