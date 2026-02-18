import Foundation

public enum ProviderName: String, Codable, CaseIterable {
    case openai
    case anthropic
    case gemini
    case apple
}

public extension ProviderName {
    var requiresCredentials: Bool {
        switch self {
        case .apple:
            return false
        case .openai, .anthropic, .gemini:
            return true
        }
    }

    var serializeProviderCalls: Bool {
        switch self {
        case .apple:
            return true
        case .openai, .anthropic, .gemini:
            return false
        }
    }
}
