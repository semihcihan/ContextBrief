import Foundation

public enum ProviderName: String, Codable, CaseIterable {
    case openai
    case anthropic
    case gemini
}

public struct ProviderConfig: Codable, Equatable {
    public let provider: ProviderName
    public var defaultModel: String
    public var keychainReference: String

    public init(provider: ProviderName, defaultModel: String, keychainReference: String) {
        self.provider = provider
        self.defaultModel = defaultModel
        self.keychainReference = keychainReference
    }
}
