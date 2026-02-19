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
    public let providerParallelWorkLimitDefault: Int
    public let providerParallelWorkLimitApple: Int?
    public let providerParallelWorkLimitOpenAI: Int?
    public let providerParallelWorkLimitAnthropic: Int?
    public let providerParallelWorkLimitGemini: Int?
    public let snapshotInactivityPromptMinutes: Int?

    public init(
        enableLocalDebugProvider: Bool? = nil,
        thirdPartyContextTitleRefreshEvery: Int? = nil,
        appleContextTitleRefreshEvery: Int? = nil,
        forcedProviderFailureChance: Double? = nil,
        providerParallelWorkLimitDefault: Int? = nil,
        providerParallelWorkLimitApple: Int? = nil,
        providerParallelWorkLimitOpenAI: Int? = nil,
        providerParallelWorkLimitAnthropic: Int? = nil,
        providerParallelWorkLimitGemini: Int? = nil,
        snapshotInactivityPromptMinutes: Int? = nil,
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
        self.providerParallelWorkLimitDefault = max(
            1,
            providerParallelWorkLimitDefault
                ?? fileOverrides.providerParallelWorkLimitDefault
                ?? 10
        )
        self.providerParallelWorkLimitApple = Self.normalizedParallelWorkLimit(
            providerParallelWorkLimitApple
                ?? fileOverrides.providerParallelWorkLimitApple
        )
        self.providerParallelWorkLimitOpenAI = Self.normalizedParallelWorkLimit(
            providerParallelWorkLimitOpenAI
                ?? fileOverrides.providerParallelWorkLimitOpenAI
        )
        self.providerParallelWorkLimitAnthropic = Self.normalizedParallelWorkLimit(
            providerParallelWorkLimitAnthropic
                ?? fileOverrides.providerParallelWorkLimitAnthropic
        )
        self.providerParallelWorkLimitGemini = Self.normalizedParallelWorkLimit(
            providerParallelWorkLimitGemini
                ?? fileOverrides.providerParallelWorkLimitGemini
        )
        self.snapshotInactivityPromptMinutes = Self.normalizedInactivityPromptMinutes(
            snapshotInactivityPromptMinutes
                ?? fileOverrides.snapshotInactivityPromptMinutes
        )
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

    public func providerParallelWorkLimit(for provider: ProviderName) -> Int {
        let providerOverride: Int?
        switch provider {
        case .apple:
            providerOverride = providerParallelWorkLimitApple
        case .openai:
            providerOverride = providerParallelWorkLimitOpenAI
        case .anthropic:
            providerOverride = providerParallelWorkLimitAnthropic
        case .gemini:
            providerOverride = providerParallelWorkLimitGemini
        }
        return max(1, providerOverride ?? providerParallelWorkLimitDefault)
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

    private static func normalizedParallelWorkLimit(_ value: Int?) -> Int? {
        guard let value else {
            return nil
        }
        return max(1, value)
    }

    private static func normalizedInactivityPromptMinutes(_ value: Int?) -> Int? {
        guard let value else {
            return nil
        }
        return max(1, value)
    }
}

private struct FileOverrides {
    let enableLocalDebugProvider: Bool?
    let thirdPartyContextTitleRefreshEvery: Int?
    let appleContextTitleRefreshEvery: Int?
    let forcedProviderFailureChance: Double?
    let providerParallelWorkLimitDefault: Int?
    let providerParallelWorkLimitApple: Int?
    let providerParallelWorkLimitOpenAI: Int?
    let providerParallelWorkLimitAnthropic: Int?
    let providerParallelWorkLimitGemini: Int?
    let snapshotInactivityPromptMinutes: Int?

    static let empty = FileOverrides(
        enableLocalDebugProvider: nil,
        thirdPartyContextTitleRefreshEvery: nil,
        appleContextTitleRefreshEvery: nil,
        forcedProviderFailureChance: nil,
        providerParallelWorkLimitDefault: nil,
        providerParallelWorkLimitApple: nil,
        providerParallelWorkLimitOpenAI: nil,
        providerParallelWorkLimitAnthropic: nil,
        providerParallelWorkLimitGemini: nil,
        snapshotInactivityPromptMinutes: nil
    )

    init(
        enableLocalDebugProvider: Bool?,
        thirdPartyContextTitleRefreshEvery: Int?,
        appleContextTitleRefreshEvery: Int?,
        forcedProviderFailureChance: Double?,
        providerParallelWorkLimitDefault: Int?,
        providerParallelWorkLimitApple: Int?,
        providerParallelWorkLimitOpenAI: Int?,
        providerParallelWorkLimitAnthropic: Int?,
        providerParallelWorkLimitGemini: Int?,
        snapshotInactivityPromptMinutes: Int?
    ) {
        self.enableLocalDebugProvider = enableLocalDebugProvider
        self.thirdPartyContextTitleRefreshEvery = thirdPartyContextTitleRefreshEvery
        self.appleContextTitleRefreshEvery = appleContextTitleRefreshEvery
        self.forcedProviderFailureChance = forcedProviderFailureChance
        self.providerParallelWorkLimitDefault = providerParallelWorkLimitDefault
        self.providerParallelWorkLimitApple = providerParallelWorkLimitApple
        self.providerParallelWorkLimitOpenAI = providerParallelWorkLimitOpenAI
        self.providerParallelWorkLimitAnthropic = providerParallelWorkLimitAnthropic
        self.providerParallelWorkLimitGemini = providerParallelWorkLimitGemini
        self.snapshotInactivityPromptMinutes = snapshotInactivityPromptMinutes
    }

    init(dictionary: [String: Any]) {
        enableLocalDebugProvider = dictionary["enableLocalDebugProvider"] as? Bool
        thirdPartyContextTitleRefreshEvery = dictionary["thirdPartyContextTitleRefreshEvery"] as? Int
        appleContextTitleRefreshEvery = dictionary["appleContextTitleRefreshEvery"] as? Int
        forcedProviderFailureChance = (dictionary["forcedProviderFailureChance"] as? NSNumber)?.doubleValue
        providerParallelWorkLimitDefault = dictionary["providerParallelWorkLimitDefault"] as? Int
        providerParallelWorkLimitApple = dictionary["providerParallelWorkLimitApple"] as? Int
        providerParallelWorkLimitOpenAI = dictionary["providerParallelWorkLimitOpenAI"] as? Int
        providerParallelWorkLimitAnthropic = dictionary["providerParallelWorkLimitAnthropic"] as? Int
        providerParallelWorkLimitGemini = dictionary["providerParallelWorkLimitGemini"] as? Int
        snapshotInactivityPromptMinutes = dictionary["snapshotInactivityPromptMinutes"] as? Int
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
