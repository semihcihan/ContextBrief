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
        var state = try repository.appState()
        state.selectedProvider = provider
        state.selectedModel = model
        try repository.saveAppState(state)
    }

    public func markOnboardingCompleted() throws {
        var state = try repository.appState()
        state.onboardingCompleted = true
        try repository.saveAppState(state)
    }

    public func state() throws -> AppState {
        try repository.appState()
    }

    public func providerSelection() throws -> ProviderSelection? {
        let state = try repository.appState()
        guard let provider = state.selectedProvider, let model = state.selectedModel else {
            return nil
        }
        return ProviderSelection(
            provider: provider,
            model: model,
            hasAPIKey: try keychain.get("api.\(provider.rawValue)") != nil
        )
    }

    public func apiKey(for provider: ProviderName) throws -> String? {
        try keychain.get("api.\(provider.rawValue)")
    }
}
