import Foundation

public protocol ProviderModelStoring {
    func setModel(_ model: String, for provider: ProviderName) throws
    func model(for provider: ProviderName) -> String?
    func deleteModel(for provider: ProviderName) throws
}

public final class UserDefaultsProviderModelStorage: ProviderModelStoring {
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "ContextBrief.model") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func setModel(_ model: String, for provider: ProviderName) throws {
        defaults.set(model, forKey: key(for: provider))
    }

    public func model(for provider: ProviderName) -> String? {
        defaults.string(forKey: key(for: provider))
    }

    public func deleteModel(for provider: ProviderName) throws {
        defaults.removeObject(forKey: key(for: provider))
    }

    private func key(for provider: ProviderName) -> String {
        "\(keyPrefix).\(provider.rawValue)"
    }
}
