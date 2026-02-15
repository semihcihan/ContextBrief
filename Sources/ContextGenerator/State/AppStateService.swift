import Foundation

public final class AppStateService {
    private let repository: ContextRepositorying
    private let keychain: KeychainServicing

    public struct ProviderSelection {
        public let provider: ProviderName
        public let model: String
        public let hasAPIKey: Bool

        public init(provider: ProviderName, model: String, hasAPIKey: Bool) {
            self.provider = provider
            self.model = model
            self.hasAPIKey = hasAPIKey
        }
    }

    public init(repository: ContextRepositorying, keychain: KeychainServicing) {
        self.repository = repository
        self.keychain = keychain
    }

    public func configureProvider(provider: ProviderName, model: String, apiKey: String?) throws {
        if let apiKey, !apiKey.isEmpty {
            try keychain.set(apiKey, for: "api.\(provider.rawValue)")
        }
        if !model.isEmpty {
            try keychain.set(model, for: modelStorageKey(for: provider))
        }
        var state = try repository.appState()
        state.selectedProvider = provider
        if !model.isEmpty {
            state.selectedModel = model
        }
        try repository.saveAppState(state)
    }

    public func markOnboardingCompleted() throws {
        var state = try repository.appState()
        state.onboardingCompleted = true
        try repository.saveAppState(state)
    }

    public func markLaunchAtLoginConfigured() throws {
        var state = try repository.appState()
        state.launchAtLoginConfigured = true
        try repository.saveAppState(state)
    }

    public func state() throws -> AppState {
        try repository.appState()
    }

    public func shortcuts() throws -> ShortcutPreferences {
        try repository.appState().shortcuts
    }

    public func updateShortcuts(_ shortcuts: ShortcutPreferences) throws {
        var state = try repository.appState()
        state.shortcuts = shortcuts
        try repository.saveAppState(state)
    }

    public func providerSelection() throws -> ProviderSelection? {
        let state = try repository.appState()
        guard let provider = state.selectedProvider else {
            return nil
        }
        let model = try keychain.get(modelStorageKey(for: provider)) ?? state.selectedModel ?? ""
        return ProviderSelection(
            provider: provider,
            model: model,
            hasAPIKey: provider == .apple ? true : ((try keychain.get("api.\(provider.rawValue)")) != nil)
        )
    }

    public func apiKey(for provider: ProviderName) throws -> String? {
        try keychain.get("api.\(provider.rawValue)")
    }

    public func model(for provider: ProviderName) throws -> String? {
        try keychain.get(modelStorageKey(for: provider))
    }

    private func modelStorageKey(for provider: ProviderName) -> String {
        "model.\(provider.rawValue)"
    }
}
