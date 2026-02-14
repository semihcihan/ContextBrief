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

        let raw = await requestText(provider: provider, model: model, apiKey: apiKey, prompt: prompt)
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

        let raw = await requestText(provider: provider, model: model, apiKey: apiKey, prompt: prompt)
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
        prompt: String
    ) async -> String? {
        do {
            switch provider {
            case .openai:
                return try await requestOpenAI(model: model, apiKey: apiKey, prompt: prompt)
            case .anthropic:
                return try await requestAnthropic(model: model, apiKey: apiKey, prompt: prompt)
            case .gemini:
                return try await requestGemini(model: model, apiKey: apiKey, prompt: prompt)
            }
        } catch {
            return nil
        }
    }

    private func requestOpenAI(model: String, apiKey: String, prompt: String) async throws -> String? {
        let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "messages": [
                ["role": "system", "content": "You generate concise names for saved work context."],
                ["role": "user", "content": prompt]
            ]
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: urlRequest)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        return message?["content"] as? String
    }

    private func requestAnthropic(model: String, apiKey: String, prompt: String) async throws -> String? {
        let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 120,
            "temperature": 0.1,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: urlRequest)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        return content?.first?["text"] as? String
    }

    private func requestGemini(model: String, apiKey: String, prompt: String) async throws -> String? {
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": ["temperature": 0.1]
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: urlRequest)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        return parts?.first?["text"] as? String
    }
}
