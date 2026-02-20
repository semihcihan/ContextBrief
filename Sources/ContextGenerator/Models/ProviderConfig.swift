import Foundation

public enum ProviderName: String, Codable, CaseIterable {
    case codex
    case claude
    case gemini
}

public extension ProviderName {
    var isCLIProvider: Bool {
        true
    }

    var requiresCredentials: Bool {
        false
    }
}
