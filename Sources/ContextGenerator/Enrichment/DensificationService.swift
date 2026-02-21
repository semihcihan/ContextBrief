import Foundation

public protocol Densifying {
    func densify(
        snapshot: CapturedSnapshot,
        provider: ProviderName,
        model: String,
        apiKey: String
    ) async throws -> (content: String, title: String?)
}

public final class DensificationService: Densifying {
    private let session: URLSession
    private let maxDensificationInputTokens: Int
    private let clientFactory: (ProviderName, URLSession) -> ProviderClient

    public init(
        session: URLSession = .shared,
        maxDensificationInputTokens: Int = 64_000,
        clientFactory: @escaping (ProviderName, URLSession) -> ProviderClient = { provider, session in
            ProviderClientFactory.make(provider: provider, session: session)
        }
    ) {
        self.session = session
        self.maxDensificationInputTokens = maxDensificationInputTokens
        self.clientFactory = clientFactory
    }

    public func densify(
        snapshot: CapturedSnapshot,
        provider: ProviderName,
        model: String,
        apiKey: String
    ) async throws -> (content: String, title: String?) {
        let inputText: String
        if
            let filtered = snapshot.filteredCombinedText?.trimmingCharacters(in: .whitespacesAndNewlines),
            !filtered.isEmpty
        {
            inputText = filtered
        } else {
            inputText = snapshot.combinedText
        }
        let estimated = TokenCountEstimator.estimate(for: inputText)
        if estimated > maxDensificationInputTokens {
            throw AppError.densificationInputTooLong(estimatedTokens: estimated, limit: maxDensificationInputTokens)
        }
        let client = clientFactory(provider, session)
        let request = DensificationRequest(
            inputText: inputText,
            appName: snapshot.appName,
            windowTitle: snapshot.windowTitle
        )
        let result = try await client.densify(
            request: request,
            apiKey: apiKey,
            model: model
        )
        let content = result.content.isEmpty ? inputText : result.content
        return (content, result.title)
    }
}
