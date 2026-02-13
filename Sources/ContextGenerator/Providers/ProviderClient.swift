import Foundation

public struct DensificationRequest {
    public let inputText: String
    public let appName: String
    public let windowTitle: String

    public init(inputText: String, appName: String, windowTitle: String) {
        self.inputText = inputText
        self.appName = appName
        self.windowTitle = windowTitle
    }
}

public protocol ProviderClient {
    var provider: ProviderName { get }
    func densify(request: DensificationRequest, apiKey: String, model: String) async throws -> String
}

public enum ProviderClientFactory {
    public static func make(provider: ProviderName, session: URLSession = .shared) -> ProviderClient {
        switch provider {
        case .openai:
            return OpenAIProviderClient(session: session)
        case .anthropic:
            return AnthropicProviderClient(session: session)
        case .google:
            return GoogleProviderClient(session: session)
        }
    }
}

private func densificationPrompt(for request: DensificationRequest) -> String {
    [
        "You are compressing captured UI/context text.",
        "Goal: remove repetitive boilerplate while preserving all meaningful facts and intent.",
        "Do not add assumptions.",
        "Return dense plain text only.",
        "App: \(request.appName)",
        "Window: \(request.windowTitle)",
        "",
        request.inputText
    ].joined(separator: "\n")
}

private struct OpenAIProviderClient: ProviderClient {
    let provider: ProviderName = .openai
    let session: URLSession

    func densify(request: DensificationRequest, apiKey: String, model: String) async throws -> String {
        let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "messages": [
                ["role": "system", "content": "You produce concise, complete context with no missing key information."],
                ["role": "user", "content": densificationPrompt(for: request)]
            ]
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: urlRequest)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String
        return content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? request.inputText
    }
}

private struct AnthropicProviderClient: ProviderClient {
    let provider: ProviderName = .anthropic
    let session: URLSession

    func densify(request: DensificationRequest, apiKey: String, model: String) async throws -> String {
        let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1400,
            "temperature": 0.1,
            "messages": [
                [
                    "role": "user",
                    "content": densificationPrompt(for: request)
                ]
            ]
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: urlRequest)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String
        return text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? request.inputText
    }
}

private struct GoogleProviderClient: ProviderClient {
    let provider: ProviderName = .google
    let session: URLSession

    func densify(request: DensificationRequest, apiKey: String, model: String) async throws -> String {
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": densificationPrompt(for: request)]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.1
            ]
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await session.data(for: urlRequest)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        let text = parts?.first?["text"] as? String
        return text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? request.inputText
    }
}
