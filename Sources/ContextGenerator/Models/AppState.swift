import Foundation

public struct AppState: Codable, Equatable {
    public var currentContextId: UUID?
    public var onboardingCompleted: Bool
    public var selectedProvider: ProviderName?
    public var selectedModel: String?
    public var shortcuts: ShortcutPreferences

    public init(
        currentContextId: UUID? = nil,
        onboardingCompleted: Bool = false,
        selectedProvider: ProviderName? = nil,
        selectedModel: String? = nil,
        shortcuts: ShortcutPreferences = .defaultValue
    ) {
        self.currentContextId = currentContextId
        self.onboardingCompleted = onboardingCompleted
        self.selectedProvider = selectedProvider
        self.selectedModel = selectedModel
        self.shortcuts = shortcuts
    }

    enum CodingKeys: String, CodingKey {
        case currentContextId
        case onboardingCompleted
        case selectedProvider
        case selectedModel
        case shortcuts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentContextId = try container.decodeIfPresent(UUID.self, forKey: .currentContextId)
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        selectedProvider = try container.decodeIfPresent(ProviderName.self, forKey: .selectedProvider)
        selectedModel = try container.decodeIfPresent(String.self, forKey: .selectedModel)
        shortcuts = try container.decodeIfPresent(ShortcutPreferences.self, forKey: .shortcuts) ?? .defaultValue
    }
}

public extension ShortcutPreferences {
    static let defaultValue = ShortcutPreferences(
        addSnapshot: ShortcutBinding(
            keyCode: 8,
            command: true,
            option: false,
            control: true,
            shift: false
        ),
        copyCurrentContext: ShortcutBinding(
            keyCode: 9,
            command: true,
            option: false,
            control: true,
            shift: false
        )
    )
}
