import Foundation
import FirebaseRemoteConfig
import ContextGenerator

extension RemoteConfig: @unchecked @retroactive Sendable {}
extension RemoteConfiguration: @unchecked Sendable {}

final class RemoteConfiguration: ConfigDefaults {
    static let shared = RemoteConfiguration()

    private let remoteConfig = RemoteConfig.remoteConfig()
    private var currentValues = ConfigDefaults()

    override init() {
#if DEBUG
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 0
        remoteConfig.configSettings = settings
#endif
        super.init()

        do {
            try remoteConfig.setDefaults(from: currentValues)
        } catch {}

        ProviderTextRequest.commonPromptProvider = { RemoteConfiguration.shared.densificationCommonPrompt }

        fetch()
    }

    required init(from decoder: Decoder) throws {
        fatalError("init(from:) has not been implemented")
    }

    private func fetch() {
        Task { [remoteConfig] in
            try? await remoteConfig.fetch()
            try? await remoteConfig.activate()
            remoteConfig.addOnConfigUpdateListener { _, _ in
                remoteConfig.activate()
            }
        }
    }

    override var densificationCommonPrompt: [String] {
        let value = remoteConfig.configValue(forKey: #function).stringValue
        if let jsonData = value.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String].self, from: jsonData),
           !parsed.isEmpty {
            return parsed
        }
        return currentValues.densificationCommonPrompt
    }
}

class ConfigDefaults: Codable {
    private(set) var densificationCommonPrompt = ProviderTextRequest.defaultCommonPrompt
}
