import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

public struct DevelopmentConfig {
    public static let shared = DevelopmentConfig()
    private static let defaultPlistFileName = "development-config.plist"
    private let appleFoundationAvailableOverride: Bool?

    public let enableAppleFoundationForTitleGeneration: Bool
    public let enableAppleFoundationForDensification: Bool
    public let thirdPartyContextTitleRefreshEvery: Int
    public let appleContextTitleRefreshEvery: Int

    public init(
        enableAppleFoundationForTitleGeneration: Bool? = nil,
        enableAppleFoundationForDensification: Bool? = nil,
        thirdPartyContextTitleRefreshEvery: Int? = nil,
        appleContextTitleRefreshEvery: Int? = nil,
        plistURL: URL? = nil,
        appleFoundationAvailableOverride: Bool? = nil
    ) {
        let fileOverrides = Self.loadPlistOverrides(plistURL: plistURL)
        self.appleFoundationAvailableOverride = appleFoundationAvailableOverride
        self.enableAppleFoundationForTitleGeneration = enableAppleFoundationForTitleGeneration
            ?? fileOverrides.enableAppleFoundationForTitleGeneration
            ?? false
        self.enableAppleFoundationForDensification = enableAppleFoundationForDensification
            ?? fileOverrides.enableAppleFoundationForDensification
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
    }

    public var appleFoundationAvailable: Bool {
        if let appleFoundationAvailableOverride {
            return appleFoundationAvailableOverride
        }
        return AppleFoundationModelSupport.isAvailable
    }

    public var appleFoundationProviderEnabled: Bool {
        appleFoundationAvailable && (enableAppleFoundationForTitleGeneration || enableAppleFoundationForDensification)
    }

    public func providerForDensification(selectedProvider: ProviderName) -> ProviderName {
        guard enableAppleFoundationForDensification, appleFoundationAvailable else {
            return selectedProvider
        }
        return .apple
    }

    public func providerForTitleGeneration(selectedProvider: ProviderName) -> ProviderName {
        guard enableAppleFoundationForTitleGeneration, appleFoundationAvailable else {
            return selectedProvider
        }
        return .apple
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
        let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return [currentDirectoryURL.appendingPathComponent(defaultPlistFileName)]
    }
}

private struct FileOverrides {
    let enableAppleFoundationForTitleGeneration: Bool?
    let enableAppleFoundationForDensification: Bool?
    let thirdPartyContextTitleRefreshEvery: Int?
    let appleContextTitleRefreshEvery: Int?

    static let empty = FileOverrides(
        enableAppleFoundationForTitleGeneration: nil,
        enableAppleFoundationForDensification: nil,
        thirdPartyContextTitleRefreshEvery: nil,
        appleContextTitleRefreshEvery: nil
    )

    init(
        enableAppleFoundationForTitleGeneration: Bool?,
        enableAppleFoundationForDensification: Bool?,
        thirdPartyContextTitleRefreshEvery: Int?,
        appleContextTitleRefreshEvery: Int?
    ) {
        self.enableAppleFoundationForTitleGeneration = enableAppleFoundationForTitleGeneration
        self.enableAppleFoundationForDensification = enableAppleFoundationForDensification
        self.thirdPartyContextTitleRefreshEvery = thirdPartyContextTitleRefreshEvery
        self.appleContextTitleRefreshEvery = appleContextTitleRefreshEvery
    }

    init(dictionary: [String: Any]) {
        enableAppleFoundationForTitleGeneration = dictionary["enableAppleFoundationForTitleGeneration"] as? Bool
        enableAppleFoundationForDensification = dictionary["enableAppleFoundationForDensification"] as? Bool
        thirdPartyContextTitleRefreshEvery = dictionary["thirdPartyContextTitleRefreshEvery"] as? Int
        appleContextTitleRefreshEvery = dictionary["appleContextTitleRefreshEvery"] as? Int
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
