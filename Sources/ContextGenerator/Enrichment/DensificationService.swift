import Foundation

public protocol Densifying {
    func densify(
        snapshot: CapturedSnapshot,
        provider: ProviderName,
        model: String,
        apiKey: String
    ) async throws -> String
}

public final class DensificationService: Densifying {
    private let session: URLSession
    private let maxDensificationInputTokens: Int

    public init(session: URLSession = .shared, maxDensificationInputTokens: Int = 64_000) {
        self.session = session
        self.maxDensificationInputTokens = maxDensificationInputTokens
    }

    public func densify(
        snapshot: CapturedSnapshot,
        provider: ProviderName,
        model: String,
        apiKey: String
    ) async throws -> String {
        let estimated = TokenCountEstimator.estimate(for: snapshot.combinedText)
        if estimated > maxDensificationInputTokens {
            throw AppError.densificationInputTooLong(estimatedTokens: estimated, limit: maxDensificationInputTokens)
        }
        let client = ProviderClientFactory.make(provider: provider, session: session)
        let request = DensificationRequest(
            inputText: snapshot.combinedText,
            appName: snapshot.appName,
            windowTitle: snapshot.windowTitle
        )

        let output = try await client.densify(
            request: request,
            apiKey: apiKey,
            model: model
        )
        return output.isEmpty ? snapshot.combinedText : output
    }
}
