import Foundation

public protocol Densifying {
    func densify(
        capture: CapturedContext,
        provider: ProviderName,
        model: String,
        apiKey: String
    ) async throws -> String
}

public final class DensificationService: Densifying {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func densify(
        capture: CapturedContext,
        provider: ProviderName,
        model: String,
        apiKey: String
    ) async throws -> String {
        let client = ProviderClientFactory.make(provider: provider, session: session)
        let request = DensificationRequest(
            inputText: capture.combinedText,
            appName: capture.appName,
            windowTitle: capture.windowTitle
        )

        let output = try await client.densify(
            request: request,
            apiKey: apiKey,
            model: model
        )
        return output.isEmpty ? capture.combinedText : output
    }
}
