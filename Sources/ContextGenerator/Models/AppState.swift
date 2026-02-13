import Foundation

public struct AppState: Codable, Equatable {
    public var currentContextId: UUID?
    public var onboardingCompleted: Bool
    public var selectedProvider: ProviderName?
    public var selectedModel: String?

    public init(
        currentContextId: UUID? = nil,
        onboardingCompleted: Bool = false,
        selectedProvider: ProviderName? = nil,
        selectedModel: String? = nil
    ) {
        self.currentContextId = currentContextId
        self.onboardingCompleted = onboardingCompleted
        self.selectedProvider = selectedProvider
        self.selectedModel = selectedModel
    }
}
