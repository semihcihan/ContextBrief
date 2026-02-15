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
        case .gemini:
            return GeminiProviderClient(session: session)
        }
    }
}

private let providerRequestTimeoutSeconds: TimeInterval = 30

private func providerRequestErrorMessage(from data: Data, fallback: String) -> String {
    guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return fallback
    }
    if let error = json["error"] as? [String: Any] {
        if let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        if let details = error["details"] as? [[String: Any]],
           let detailMessage = details.first?["message"] as? String,
           !detailMessage.isEmpty
        {
            return detailMessage
        }
    }
    if let message = json["message"] as? String, !message.isEmpty {
        return message
    }
    return fallback
}

private func validatedResponseData(
    _ data: Data,
    _ response: URLResponse,
    providerName: String
) throws -> Data {
    guard let httpResponse = response as? HTTPURLResponse else {
        throw AppError.providerRequestFailed("Unexpected response from \(providerName) API.")
    }
    guard (200 ... 299).contains(httpResponse.statusCode) else {
        let fallback = "Request to \(providerName) failed with status \(httpResponse.statusCode)."
        let details = providerRequestErrorMessage(from: data, fallback: fallback)
        throw AppError.providerRequestFailed(details)
    }
    return data
}

private func requestData(
    session: URLSession,
    request: URLRequest,
    providerName: String
) async throws -> Data {
    do {
        let (data, response) = try await session.data(for: request)
        return try validatedResponseData(data, response, providerName: providerName)
    } catch let appError as AppError {
        throw appError
    } catch let urlError as URLError where urlError.code == .timedOut {
        throw AppError.providerRequestFailed(
            "\(providerName) request timed out. Check network access and try again."
        )
    } catch {
        throw AppError.providerRequestFailed(
            "Unable to reach \(providerName) API: \(error.localizedDescription)"
        )
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
        urlRequest.timeoutInterval = providerRequestTimeoutSeconds
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

        let validatedData = try await requestData(session: session, request: urlRequest, providerName: "OpenAI")
        let json = try JSONSerialization.jsonObject(with: validatedData) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String
        guard let text = content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw AppError.providerRequestFailed("OpenAI returned an empty response. Check model and account status.")
        }
        return text
    }
}

private struct AnthropicProviderClient: ProviderClient {
    let provider: ProviderName = .anthropic
    let session: URLSession

    func densify(request: DensificationRequest, apiKey: String, model: String) async throws -> String {
        let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = providerRequestTimeoutSeconds
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

        let validatedData = try await requestData(session: session, request: urlRequest, providerName: "Anthropic")
        let json = try JSONSerialization.jsonObject(with: validatedData) as? [String: Any]
        let content = json?["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String
        guard let normalized = text?.trimmingCharacters(in: .whitespacesAndNewlines), !normalized.isEmpty else {
            throw AppError.providerRequestFailed("Anthropic returned an empty response. Check model and account status.")
        }
        return normalized
    }
}

private struct GeminiProviderClient: ProviderClient {
    let provider: ProviderName = .gemini
    let session: URLSession

    func densify(request: DensificationRequest, apiKey: String, model: String) async throws -> String {
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = providerRequestTimeoutSeconds
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

        let validatedData = try await requestData(session: session, request: urlRequest, providerName: "Gemini")
        let json = try JSONSerialization.jsonObject(with: validatedData) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        let text = parts?.first?["text"] as? String
        guard let normalized = text?.trimmingCharacters(in: .whitespacesAndNewlines), !normalized.isEmpty else {
            throw AppError.providerRequestFailed("Gemini returned an empty response. Check model and account status.")
        }
        return normalized
    }
}
