import Foundation

public final class AppStateService {
    private let repository: ContextRepositorying
    private let modelStorage: ProviderModelStoring

    public struct ProviderSelection {
        public let provider: ProviderName
        public let model: String

        public init(provider: ProviderName, model: String) {
            self.provider = provider
            self.model = model
        }
    }

    public init(repository: ContextRepositorying, modelStorage: ProviderModelStoring) {
        self.repository = repository
        self.modelStorage = modelStorage
    }

    public func configureProvider(provider: ProviderName, model: String, apiKey: String? = nil) throws {
        if !model.isEmpty {
            try modelStorage.setModel(model, for: provider)
        } else {
            try? modelStorage.deleteModel(for: provider)
        }
        var state = try repository.appState()
        state.selectedProvider = provider
        state.selectedModel = model.isEmpty ? nil : model
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
        let model = modelStorage.model(for: provider) ?? state.selectedModel ?? ""
        return ProviderSelection(provider: provider, model: model)
    }

    public func model(for provider: ProviderName) throws -> String? {
        modelStorage.model(for: provider)
    }
}
