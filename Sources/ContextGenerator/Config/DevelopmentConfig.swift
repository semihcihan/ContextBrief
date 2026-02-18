import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

public struct DevelopmentConfig {
    public static let shared = DevelopmentConfig()
    private static let defaultPlistFileName = "config.plist"
    private static let isDebugBuild: Bool = {
#if DEBUG
        true
#else
        false
#endif
    }()
    private let appleFoundationAvailableOverride: Bool?

    public let enableLocalDebugProvider: Bool
    public let thirdPartyContextTitleRefreshEvery: Int
    public let appleContextTitleRefreshEvery: Int
    public let forcedProviderFailureChance: Double

    public init(
        enableLocalDebugProvider: Bool? = nil,
        thirdPartyContextTitleRefreshEvery: Int? = nil,
        appleContextTitleRefreshEvery: Int? = nil,
        forcedProviderFailureChance: Double? = nil,
        plistURL: URL? = nil,
        appleFoundationAvailableOverride: Bool? = nil
    ) {
        let fileOverrides = Self.loadPlistOverrides(plistURL: plistURL)
        self.appleFoundationAvailableOverride = appleFoundationAvailableOverride
        self.enableLocalDebugProvider = enableLocalDebugProvider
            ?? fileOverrides.enableLocalDebugProvider
            ?? false
        self.thirdPartyContextTitleRefreshEvery = max(
            1,
            thirdPartyContextTitleRefreshEvery
                ?? fileOverrides.thirdPartyContextTitleRefreshEvery
                ?? 3
        )
        self.appleContextTitleRefreshEvery = max(
            1,
            appleContextTitleRefreshEvery
                ?? fileOverrides.appleContextTitleRefreshEvery
                ?? 6
        )
        self.forcedProviderFailureChance = Self.isDebugBuild
            ? min(
                1,
                max(
                    0,
                    forcedProviderFailureChance
                        ?? fileOverrides.forcedProviderFailureChance
                        ?? 0
                )
            )
            : 0
    }

    public var appleFoundationAvailable: Bool {
        if let appleFoundationAvailableOverride {
            return appleFoundationAvailableOverride
        }
        return AppleFoundationModelSupport.isAvailable
    }

    public var appleFoundationProviderEnabled: Bool {
        appleFoundationAvailable
    }

    public var localDebugResponsesEnabled: Bool {
        Self.isDebugBuild && enableLocalDebugProvider
    }

    public func providerForDensification(selectedProvider: ProviderName) -> ProviderName {
        selectedProvider
    }

    public func providerForTitleGeneration(selectedProvider: ProviderName) -> ProviderName {
        selectedProvider
    }

    public func requiresCredentials(for provider: ProviderName) -> Bool {
        guard !localDebugResponsesEnabled else {
            return false
        }
        return provider.requiresCredentials
    }

    public func contextTitleRefreshEvery(for provider: ProviderName) -> Int {
        provider == .apple
            ? appleContextTitleRefreshEvery
            : thirdPartyContextTitleRefreshEvery
    }

    private static func loadPlistOverrides(plistURL: URL?) -> FileOverrides {
        for path in plistCandidatePaths(plistURL: plistURL) {
            if
                let dictionary = NSDictionary(contentsOf: path) as? [String: Any],
                !dictionary.isEmpty
            {
                return FileOverrides(dictionary: dictionary)
            }
        }
        return .empty
    }

    private static func plistCandidatePaths(plistURL: URL?) -> [URL] {
        if let plistURL {
            return [plistURL]
        }
        var candidates: [URL] = []
        if let bundleConfigURL = Bundle.main.url(forResource: "config", withExtension: "plist") {
            candidates.append(bundleConfigURL)
        }
        let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        candidates.append(currentDirectoryURL.appendingPathComponent("Sources/ContextGeneratorApp/Resources/\(defaultPlistFileName)"))
        candidates.append(currentDirectoryURL.appendingPathComponent(defaultPlistFileName))
        return candidates
    }
}

private struct FileOverrides {
    let enableLocalDebugProvider: Bool?
    let thirdPartyContextTitleRefreshEvery: Int?
    let appleContextTitleRefreshEvery: Int?
    let forcedProviderFailureChance: Double?

    static let empty = FileOverrides(
        enableLocalDebugProvider: nil,
        thirdPartyContextTitleRefreshEvery: nil,
        appleContextTitleRefreshEvery: nil,
        forcedProviderFailureChance: nil
    )

    init(
        enableLocalDebugProvider: Bool?,
        thirdPartyContextTitleRefreshEvery: Int?,
        appleContextTitleRefreshEvery: Int?,
        forcedProviderFailureChance: Double?
    ) {
        self.enableLocalDebugProvider = enableLocalDebugProvider
        self.thirdPartyContextTitleRefreshEvery = thirdPartyContextTitleRefreshEvery
        self.appleContextTitleRefreshEvery = appleContextTitleRefreshEvery
        self.forcedProviderFailureChance = forcedProviderFailureChance
    }

    init(dictionary: [String: Any]) {
        enableLocalDebugProvider = dictionary["enableLocalDebugProvider"] as? Bool
        thirdPartyContextTitleRefreshEvery = dictionary["thirdPartyContextTitleRefreshEvery"] as? Int
        appleContextTitleRefreshEvery = dictionary["appleContextTitleRefreshEvery"] as? Int
        forcedProviderFailureChance = (dictionary["forcedProviderFailureChance"] as? NSNumber)?.doubleValue
    }
}

public enum AppleFoundationModelSupport {
    public static var isAvailable: Bool {
#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
#endif
        return false
    }
}
