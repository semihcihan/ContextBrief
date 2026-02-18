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
        try await forceFailure()
        if DevelopmentConfig.shared.localDebugResponsesEnabled {
            AppLogger.debug("Local debug response enabled.")
            try await Task.sleep(nanoseconds: localDebugResponseDelayNanoseconds)
            return localDebugPrefixText(request.inputText, maxCharacters: localDebugDensificationCharacterLimit)
        }
        do {
            return try await requestText(
                request: ProviderTextRequest(
                    systemInstruction: densificationSystemInstruction,
                    prompt: densificationPrompt(for: request)
                ),
                apiKey: apiKey,
                model: model
            )
        } catch {
            guard isContextWindowExceededError(error) else {
                throw error
            }
            AppLogger.debug(
                "Densification exceeded \(provider.rawValue) context window. Retrying with chunking fallback."
            )
            return try await densifyWithAdaptiveChunking(
                request: request,
                apiKey: apiKey,
                model: model,
                initialChunkInputTokens: reactiveContextWindowInitialChunkInputTokens
            )
        }
    }
}

private extension ProviderClient {
    func forceFailure() async throws {
        let forcedFailureChance = DevelopmentConfig.shared.forcedProviderFailureChance
        guard forcedFailureChance > 0 else {
            return
        }
        let randomValue = Double.random(in: 0 ... 1)
        if randomValue < forcedFailureChance {
            try await Task.sleep(nanoseconds: localDebugResponseDelayNanoseconds)
            throw AppError.providerRequestFailed("Forced provider failure for debugging.")
        }
    }

    func densifyWithAdaptiveChunking(
        request: DensificationRequest,
        apiKey: String,
        model: String,
        initialChunkInputTokens: Int
    ) async throws -> String {
        var chunkInputTokens = max(densificationMinimumChunkInputTokens, initialChunkInputTokens)
        while true {
            do {
                return try await densifyInChunks(
                    request: request,
                    apiKey: apiKey,
                    model: model,
                    chunkInputTokens: chunkInputTokens
                )
            } catch {
                guard isContextWindowExceededError(error), chunkInputTokens > densificationMinimumChunkInputTokens else {
                    throw error
                }
                let nextChunkInputTokens = max(densificationMinimumChunkInputTokens, chunkInputTokens / 2)
                guard nextChunkInputTokens < chunkInputTokens else {
                    throw error
                }
                AppLogger.debug(
                    "Densification exceeded context window. Retrying with smaller chunk budget [provider=\(provider.rawValue) previous=\(chunkInputTokens) next=\(nextChunkInputTokens)]"
                )
                chunkInputTokens = nextChunkInputTokens
            }
        }
    }

    func densifyInChunks(
        request: DensificationRequest,
        apiKey: String,
        model: String,
        chunkInputTokens: Int
    ) async throws -> String {
        let planner = AppleFoundationContextWindowPlanner(
            maxChunkInputTokens: chunkInputTokens,
            maxMergeInputTokens: max(
                densificationMinimumChunkInputTokens,
                min(chunkInputTokens, densificationDefaultMergeInputTokens)
            ),
            minimumChunkInputTokens: densificationMinimumChunkInputTokens
        )
        let chunks = planner.chunkInput(request.inputText)
        guard !chunks.isEmpty else {
            return ""
        }

        var partials: [String] = []
        partials.reserveCapacity(chunks.count)
        for (index, chunk) in chunks.enumerated() {
            partials.append(
                try await requestText(
                    request: ProviderTextRequest(
                        systemInstruction: densificationSystemInstruction,
                        prompt: densificationChunkPrompt(
                            inputText: chunk,
                            appName: request.appName,
                            windowTitle: request.windowTitle,
                            chunkIndex: index + 1,
                            totalChunks: chunks.count
                        )
                    ),
                    apiKey: apiKey,
                    model: model
                )
            )
        }

        var mergedPartials = partials
        var pass = 1
        while mergedPartials.count > 1 {
            let mergeGroups = planner.mergeGroups(for: mergedPartials)
            if mergeGroups.count == mergedPartials.count, mergeGroups.allSatisfy({ $0.count == 1 }) {
                return mergedPartials.joined(separator: "\n\n")
            }

            var reducedPartials: [String] = []
            reducedPartials.reserveCapacity(mergeGroups.count)
            for group in mergeGroups {
                reducedPartials.append(
                    try await requestText(
                        request: ProviderTextRequest(
                            systemInstruction: densificationSystemInstruction,
                            prompt: densificationMergePrompt(
                                partials: group,
                                appName: request.appName,
                                windowTitle: request.windowTitle,
                                pass: pass
                            )
                        ),
                        apiKey: apiKey,
                        model: model
                    )
                )
            }
            mergedPartials = reducedPartials
            pass += 1
        }

        return mergedPartials.first ?? ""
    }
}

public enum ProviderClientFactory {
    public static func make(provider: ProviderName, session: URLSession = .shared) -> ProviderClient {
        let client: ProviderClient
        switch provider {
        case .openai:
            client = OpenAIProviderClient(session: session)
        case .anthropic:
            client = AnthropicProviderClient(session: session)
        case .gemini:
            client = GeminiProviderClient(session: session)
        case .apple:
            client = AppleFoundationProviderClient()
        }
        if provider.serializeProviderCalls {
            return SerializedProviderClient(provider: provider, wrapped: client)
        }
        return client
    }
}

actor ProviderCallSerializer {
    static let shared = ProviderCallSerializer()
    private var activeProviders: Set<String> = []
    private var waitersByProvider: [String: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(provider: ProviderName) async {
        let key = provider.rawValue
        if !activeProviders.contains(key) {
            activeProviders.insert(key)
            return
        }
        await withCheckedContinuation { continuation in
            waitersByProvider[key, default: []].append(continuation)
        }
    }

    func release(provider: ProviderName) {
        let key = provider.rawValue
        guard var waiters = waitersByProvider[key], !waiters.isEmpty else {
            activeProviders.remove(key)
            waitersByProvider[key] = nil
            return
        }
        let next = waiters.removeFirst()
        if waiters.isEmpty {
            waitersByProvider[key] = nil
        } else {
            waitersByProvider[key] = waiters
        }
        next.resume()
    }
}

struct SerializedProviderClient: ProviderClient {
    let provider: ProviderName
    let wrapped: ProviderClient

    func requestText(request: ProviderTextRequest, apiKey: String, model: String) async throws -> String {
        try await runSerialized {
            try await wrapped.requestText(request: request, apiKey: apiKey, model: model)
        }
    }

    func densify(request: DensificationRequest, apiKey: String, model: String) async throws -> String {
        try await runSerialized {
            try await wrapped.densify(request: request, apiKey: apiKey, model: model)
        }
    }

    private func runSerialized<T>(_ operation: () async throws -> T) async throws -> T {
        let serializer = ProviderCallSerializer.shared
        await serializer.acquire(provider: provider)
        do {
            let result = try await operation()
            await serializer.release(provider: provider)
            return result
        } catch {
            await serializer.release(provider: provider)
            throw error
        }
    }
}

private let providerRequestTimeoutSeconds: TimeInterval = 30
private let localDebugResponseDelayNanoseconds: UInt64 = 3_000_000_000
private let localDebugDensificationCharacterLimit = 200
private let densificationSystemInstruction = "You produce concise, complete context with no missing key information."
private let appleProactiveInitialChunkInputTokens = 1800
private let densificationMinimumChunkInputTokens = 320
private let reactiveContextWindowInitialChunkInputTokens = 12_000
private let densificationDefaultMergeInputTokens = 2_000
private let densificationChunkTargetWordLimit = 180
private let densificationMergeTargetWordLimit = 260
private let appleContextWindowExceededMessage = "Context Window Size Exceeded. Apple Foundation Models allow up to 4,096 tokens per session (including instructions, input, and output). Start a new session and retry with shorter input or output."

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
        if
            let signal = providerErrorSignal(from: data),
            isContextWindowExceededSignal(signal),
            !isContextWindowExceededSignal(details)
        {
            throw AppError.providerRequestFailed("Context window exceeded. \(details)")
        }
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

private func providerErrorSignal(from data: Data) -> String? {
    guard
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return nil
    }

    var parts: [String] = []
    func appendField(_ raw: Any?) {
        guard let raw else {
            return
        }
        let value: String
        if let stringValue = raw as? String {
            value = stringValue
        } else {
            value = String(describing: raw)
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        parts.append(trimmed)
    }

    if let error = json["error"] as? [String: Any] {
        appendField(error["message"])
        appendField(error["type"])
        appendField(error["code"])
        appendField(error["status"])
        if let details = error["details"] as? [[String: Any]] {
            for detail in details {
                appendField(detail["message"])
                appendField(detail["reason"])
                appendField(detail["code"])
                appendField(detail["status"])
                appendField(detail["@type"])
            }
        }
    }

    appendField(json["message"])
    appendField(json["status"])
    appendField(json["error_description"])

    let signal = parts.joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !signal.isEmpty else {
        return nil
    }
    return signal
}

private func isContextWindowExceededError(_ error: Error) -> Bool {
    if let appError = error as? AppError {
        guard case let .providerRequestFailed(details) = appError else {
            return false
        }
        return isContextWindowExceededSignal(details)
    }
    return isRawContextWindowExceededError(error)
}

private func isRawContextWindowExceededError(_ error: Error) -> Bool {
    let nsError = error as NSError
    let signal = [
        String(describing: error),
        nsError.domain,
        nsError.localizedDescription,
        nsError.userInfo.description
    ].joined(separator: " ")
    return isContextWindowExceededSignal(signal)
}

private func isContextWindowExceededSignal(_ rawSignal: String) -> Bool {
    let signal = rawSignal.lowercased()
    guard !signal.isEmpty else {
        return false
    }
    if signal.contains("exceededcontextwindowsize")
        || signal.contains("context window")
        || signal.contains("contextwindow")
        || signal.contains("context_length_exceeded")
        || signal.contains("maximum context length")
        || signal.contains("max context length")
        || signal.contains("prompt is too long")
        || signal.contains("input token count")
        || signal.contains("maximum number of tokens allowed")
    {
        return true
    }
    if signal.contains("rate limit")
        || signal.contains("tokens per minute")
        || signal.contains("requests per minute")
        || signal.contains("input_tokens")
        || signal.contains("output_tokens")
        || signal.contains("tpm")
        || signal.contains("rpm")
        || signal.contains("quota")
    {
        return false
    }
    let hasTokenLanguage = signal.contains("token")
    let hasPromptLanguage = signal.contains("input")
        || signal.contains("prompt")
        || signal.contains("message")
        || signal.contains("messages")
    let hasWindowLanguage = signal.contains("context")
        || signal.contains("maximum")
        || signal.contains("max ")
        || signal.contains("allowed")
    let hasExceededLanguage = signal.contains("exceed")
        || signal.contains("limit")
        || signal.contains("too long")
        || signal.contains("too large")
        || signal.contains("over")
    return hasTokenLanguage && hasPromptLanguage && hasWindowLanguage && hasExceededLanguage
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

    func densify(request: DensificationRequest, apiKey: String, model: String) async throws -> String {
        try await forceFailure()
        if DevelopmentConfig.shared.localDebugResponsesEnabled {
            AppLogger.debug("Local debug response enabled.")
            try await Task.sleep(nanoseconds: localDebugResponseDelayNanoseconds)
            return localDebugPrefixText(request.inputText, maxCharacters: localDebugDensificationCharacterLimit)
        }

#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.availability == .available else {
                throw AppError.providerRequestFailed(
                    "Apple Foundation Models are not available on this Mac."
                )
            }

            return try await densifyWithAdaptiveChunking(
                request: request,
                apiKey: apiKey,
                model: model,
                initialChunkInputTokens: appleProactiveInitialChunkInputTokens
            )
        }
#endif
        throw AppError.providerRequestFailed(
            "Apple Foundation Models are unavailable in this environment."
        )
    }

    func requestText(request: ProviderTextRequest, apiKey: String, model: String) async throws -> String {
#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.availability == .available else {
                throw AppError.providerRequestFailed(
                    "Apple Foundation Models are not available on this Mac."
                )
            }
            let session = makeLanguageModelSession(systemInstruction: request.systemInstruction)
            do {
                let response = try await session.respond(to: request.prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    throw AppError.providerRequestFailed("Apple Foundation Models returned an empty response.")
                }
                return text
            } catch let appError as AppError {
                throw appError
            } catch {
                throw mappedAppleFoundationError(error)
            }
        }
#endif
        throw AppError.providerRequestFailed(
            "Apple Foundation Models are unavailable in this environment."
        )
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private extension AppleFoundationProviderClient {
    func makeLanguageModelSession(systemInstruction: String?) -> LanguageModelSession {
        if
            let instruction = systemInstruction?.trimmingCharacters(in: .whitespacesAndNewlines),
            !instruction.isEmpty
        {
            return LanguageModelSession(instructions: instruction)
        }
        return LanguageModelSession()
    }

    func mappedAppleFoundationError(_ error: Error) -> AppError {
        if isRawContextWindowExceededError(error) {
            return .providerRequestFailed(appleContextWindowExceededMessage)
        }
        return .providerRequestFailed("Apple Foundation Models request failed: \(error.localizedDescription)")
    }
}
#endif

private func densificationChunkPrompt(
    inputText: String,
    appName: String,
    windowTitle: String,
    chunkIndex: Int,
    totalChunks: Int
) -> String {
    [
        "Process this chunk from one captured snapshot.",
        "Chunk \(chunkIndex) of \(totalChunks).",
        "Keep facts, intent, actions, outcomes, constraints, and errors.",
        "Remove low-signal UI chrome and duplicates.",
        "Return dense plain text only.",
        "Target length: <= \(densificationChunkTargetWordLimit) words.",
        "App: \(appName)",
        "Window: \(windowTitle)",
        "",
        inputText
    ].joined(separator: "\n")
}

private func densificationMergePrompt(
    partials: [String],
    appName: String,
    windowTitle: String,
    pass: Int
) -> String {
    [
        "Merge these partial summaries into one complete snapshot context.",
        "Pass \(pass).",
        "Keep high-signal facts, intent, actions, outcomes, constraints, and errors.",
        "Remove duplicates and contradictions.",
        "Return dense plain text only.",
        "Target length: <= \(densificationMergeTargetWordLimit) words.",
        "App: \(appName)",
        "Window: \(windowTitle)",
        "",
        partials.enumerated().map { index, partial in
            "[\(index + 1)] \(partial)"
        }.joined(separator: "\n\n")
    ].joined(separator: "\n")
}
