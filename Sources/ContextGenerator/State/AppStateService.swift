import Foundation

public final class AppStateService {
    private let repository: ContextRepositorying
    private let keychain: KeychainServicing

    public init(repository: ContextRepositorying, keychain: KeychainServicing) {
        self.repository = repository
        self.keychain = keychain
    }

    public func configureProvider(provider: ProviderName, model: String, apiKey: String) throws {
        try keychain.set(apiKey, for: "api.\(provider.rawValue)")
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
}
