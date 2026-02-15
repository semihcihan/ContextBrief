import Foundation

public enum ProviderName: String, Codable, CaseIterable {
    case openai
    case anthropic
    case gemini
    case apple
}
