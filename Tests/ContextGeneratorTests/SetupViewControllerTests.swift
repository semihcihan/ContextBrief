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
    func testShowsCLIToolsAndSelectsCodexByDefault() throws {
        let (appStateService, _) = try makeAppStateService()
        let controller = makeController(
            appStateService: appStateService,
            developmentConfig: defaultDevelopmentConfig()
        )
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.testingProviderTitles(), ["Codex", "Claude Code", "Gemini"])
        XCTAssertEqual(controller.testingSelectedProvider(), .codex)
        XCTAssertEqual(controller.testingInfoLabelValue(), "Codex selected. Model is optional.")
        XCTAssertFalse(controller.testingAPIKeyRowVisible())
        XCTAssertTrue(controller.testingModelRowVisible())
    }

    func testSelectingClaudeUpdatesInfoAndDefaultModel() throws {
        let (appStateService, _) = try makeAppStateService()
        let controller = makeController(
            appStateService: appStateService,
            developmentConfig: defaultDevelopmentConfig()
        )
        controller.loadViewIfNeeded()
        controller.testingSelectProvider(.claude)

        XCTAssertEqual(controller.testingSelectedProvider(), .claude)
        XCTAssertEqual(controller.testingModelValue(), "claude-haiku-4-5")
        XCTAssertEqual(controller.testingInfoLabelValue(), "Claude Code selected. Model is optional.")
        XCTAssertFalse(controller.testingAPIKeyRowVisible())
    }

    func testCompletedSetupLoadsWithNeutralInfoAndDisabledSaveChanges() throws {
        let (appStateService, _) = try makeAppStateService()
        try appStateService.configureProvider(provider: .codex, model: "gpt-5-nano", apiKey: nil)
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

    func testCompletedSetupEnablesSaveChangesWhenModelChanges() throws {
        let (appStateService, _) = try makeAppStateService()
        try appStateService.configureProvider(provider: .codex, model: "gpt-5-nano", apiKey: nil)
        try appStateService.markOnboardingCompleted()

        let controller = makeController(
            appStateService: appStateService,
            developmentConfig: defaultDevelopmentConfig()
        )
        controller.loadViewIfNeeded()
        controller.testingSetModelValue("gpt-5")

        XCTAssertEqual(controller.testingFinishSetupButtonTitle(), "Save Changes")
        XCTAssertTrue(controller.testingFinishSetupButtonEnabled())
        XCTAssertFalse(controller.testingSetupCompleteBadgeVisible())
    }

    func testIncompleteOnboardingUsesFinishSetupWithActionableInfo() throws {
        let (appStateService, _) = try makeAppStateService()
        try appStateService.configureProvider(provider: .codex, model: "gpt-5-codex", apiKey: nil)

        let controller = makeController(
            appStateService: appStateService,
            developmentConfig: defaultDevelopmentConfig()
        )
        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.testingInfoLabelValue(), "Codex selected. Model is optional.")
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
            enableLocalDebugProvider: false,
            appleFoundationAvailableOverride: false
        )
    }
}
