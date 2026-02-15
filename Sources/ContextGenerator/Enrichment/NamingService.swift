import Foundation

public final class NamingService {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func suggestSnapshotTitle(
        capturedSnapshot: CapturedSnapshot,
        denseContent: String,
        provider: ProviderName,
        model: String,
        apiKey: String,
        fallback: String
    ) async -> String {
        let prompt = [
            "Create a short snapshot title (max 6 words).",
            "Output only the title. No punctuation unless necessary.",
            "App: \(capturedSnapshot.appName)",
            "Window: \(capturedSnapshot.windowTitle)",
            "",
            denseContent
        ].joined(separator: "\n")

        let raw = await requestText(
            provider: provider,
            model: model,
            apiKey: apiKey,
            systemInstruction: "You generate concise names for saved work context.",
            prompt: prompt
        )
        return normalizedTitle(raw, fallback: fallback)
    }

    public func suggestContextTitle(
        snapshots: [Snapshot],
        provider: ProviderName,
        model: String,
        apiKey: String,
        fallback: String
    ) async -> String {
        let joined = snapshots.suffix(4).map { snapshot in
            "[\(snapshot.sequence)] \(snapshot.denseContent)"
        }.joined(separator: "\n\n")
        let prompt = [
            "Create a short context title (max 6 words).",
            "Reflect the shared user task/intent across these snapshots.",
            "Output only the title.",
            "",
            joined
        ].joined(separator: "\n")

        let raw = await requestText(
            provider: provider,
            model: model,
            apiKey: apiKey,
            systemInstruction: "You generate concise names for saved work context.",
            prompt: prompt
        )
        return normalizedTitle(raw, fallback: fallback)
    }

    private func normalizedTitle(_ value: String?, fallback: String) -> String {
        let cleaned =
            value?
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        if cleaned.isEmpty {
            return fallback
        }
        return String(cleaned.prefix(80))
    }

    private func requestText(
        provider: ProviderName,
        model: String,
        apiKey: String,
        systemInstruction: String? = nil,
        prompt: String
    ) async -> String? {
        do {
            let client = ProviderClientFactory.make(provider: provider, session: session)
            return try await client.requestText(
                request: ProviderTextRequest(systemInstruction: systemInstruction, prompt: prompt),
                apiKey: apiKey,
                model: model
            )
        } catch {
            return nil
        }
    }
}
