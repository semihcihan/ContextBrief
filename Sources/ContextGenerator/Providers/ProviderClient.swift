import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

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

public struct ProviderTextRequest {
    public let systemInstruction: String?
    public let prompt: String

    public init(systemInstruction: String? = nil, prompt: String) {
        self.systemInstruction = systemInstruction
        self.prompt = prompt
    }
}

public protocol ProviderClient {
    var provider: ProviderName { get }
    func requestText(request: ProviderTextRequest, apiKey: String, model: String) async throws -> String
    func densify(request: DensificationRequest, apiKey: String, model: String) async throws -> String
}

public extension ProviderClient {
    func densify(request: DensificationRequest, apiKey: String, model: String) async throws -> String {
        if DevelopmentConfig.shared.localDebugResponsesEnabled {
            AppLogger.debug("Local debug response enabled.")
            try await Task.sleep(nanoseconds: localDebugResponseDelayNanoseconds)
            return localDebugPrefixText(request.inputText, maxCharacters: localDebugDensificationCharacterLimit)
        }
        return try await requestText(
            request: ProviderTextRequest(
                systemInstruction: "You produce concise, complete context with no missing key information.",
                prompt: densificationPrompt(for: request)
            ),
            apiKey: apiKey,
            model: model
        )
    }
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
        case .apple:
            return AppleFoundationProviderClient()
        }
    }
}

private let providerRequestTimeoutSeconds: TimeInterval = 30
private let localDebugResponseDelayNanoseconds: UInt64 = 3_000_000_000
private let localDebugDensificationCharacterLimit = 200

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
        "You are extracting the essential context from captured UI text.",
        "Keep meaningful facts, intent, actions, outcomes, constraints, and errors.",
        "Remove low-signal UI noise such as nav labels, menu items, generic button text, repeated form labels, and boilerplate chrome.",
        "Keep UI text only when it changes meaning (for example selected options, warnings, status, or action-specific labels).",
        "Do not add assumptions.",
        "Return dense plain text only.",
        "App: \(request.appName)",
        "Window: \(request.windowTitle)",
        "",
        request.inputText
    ].joined(separator: "\n")
}

private func localDebugPrefixText(_ value: String, maxCharacters: Int) -> String {
    String(value.prefix(maxCharacters))
}

private struct OpenAIProviderClient: ProviderClient {
    let provider: ProviderName = .openai
    let session: URLSession

    func requestText(request: ProviderTextRequest, apiKey: String, model: String) async throws -> String {
        let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = providerRequestTimeoutSeconds
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var messages: [[String: Any]] = []
        if
            let systemInstruction = request.systemInstruction?.trimmingCharacters(in: .whitespacesAndNewlines),
            !systemInstruction.isEmpty
        {
            messages.append(["role": "system", "content": systemInstruction])
        }
        messages.append(["role": "user", "content": request.prompt])

        let body: [String: Any] = [
            "model": model,
            "messages": messages
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

    func requestText(request: ProviderTextRequest, apiKey: String, model: String) async throws -> String {
        let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = providerRequestTimeoutSeconds
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 1400,
            "messages": [
                [
                    "role": "user",
                    "content": request.prompt
                ]
            ]
        ]
        if
            let systemInstruction = request.systemInstruction?.trimmingCharacters(in: .whitespacesAndNewlines),
            !systemInstruction.isEmpty
        {
            body["system"] = systemInstruction
        }
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

    func requestText(request: ProviderTextRequest, apiKey: String, model: String) async throws -> String {
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = providerRequestTimeoutSeconds
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": request.prompt]
                    ]
                ]
            ]
        ]
        if
            let systemInstruction = request.systemInstruction?.trimmingCharacters(in: .whitespacesAndNewlines),
            !systemInstruction.isEmpty
        {
            body["system_instruction"] = ["parts": [["text": systemInstruction]]]
        }
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

private struct AppleFoundationProviderClient: ProviderClient {
    let provider: ProviderName = .apple

    func requestText(request: ProviderTextRequest, apiKey: String, model: String) async throws -> String {
#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.availability == .available else {
                throw AppError.providerRequestFailed(
                    "Apple Foundation Models are not available on this Mac."
                )
            }
            let session: LanguageModelSession
            if
                let instruction = request.systemInstruction?.trimmingCharacters(in: .whitespacesAndNewlines),
                !instruction.isEmpty
            {
                session = LanguageModelSession(instructions: instruction)
            } else {
                session = LanguageModelSession()
            }
            let response = try await session.respond(to: request.prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw AppError.providerRequestFailed("Apple Foundation Models returned an empty response.")
            }
            return text
        }
#endif
        throw AppError.providerRequestFailed(
            "Apple Foundation Models are unavailable in this environment."
        )
    }
}
