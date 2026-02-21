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

public struct ProviderTextRequest {
    static let commonPrompt = [
        "Keep meaningful facts, intent, actions, outcomes, constraints, and errors.",
        "Remove low-signal UI noise such as nav labels, menu items, generic button text, repeated form labels, and boilerplate chrome.",
        "Keep UI text only when it changes meaning (for example selected options, warnings, status, or action-specific labels).",
        "Do not add assumptions.",
        "Return dense plain text only.",
    ]
    public let systemInstruction: String?
    public let prompt: String

    public init(systemInstruction: String? = nil, prompt: String) {
        self.systemInstruction = (systemInstruction ?? "") + "\n" + ProviderTextRequest.commonPrompt.joined(separator: "\n")
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
        let startedAt = Date()
        try await forceFailure()
        if DevelopmentConfig.shared.localDebugResponsesEnabled {
            AppLogger.debug("Local debug response enabled.")
            try await Task.sleep(nanoseconds: localDebugResponseDelayNanoseconds)
            let output = localDebugPrefixText(request.inputText, maxCharacters: localDebugDensificationCharacterLimit)
            AppLogger.debug(
                "Densification completed [provider=\(provider.rawValue) runs=1 seconds=\(formattedElapsedSeconds(since: startedAt))]"
            )
            return output
        }
        let output = try await requestText(
            request: ProviderTextRequest(
                systemInstruction: densificationSystemInstruction,
                prompt: densificationPrompt(for: request)
            ),
            apiKey: apiKey,
            model: model
        )
        AppLogger.debug(
            "Densification completed [provider=\(provider.rawValue) runs=1 seconds=\(formattedElapsedSeconds(since: startedAt))]"
        )
        return output
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
}

public enum ProviderClientFactory {
    public static func make(provider: ProviderName, session: URLSession = .shared) -> ProviderClient {
        _ = session
        switch provider {
        case .codex:
            return CodexCLIProviderClient()
        case .claude:
            return ClaudeCLIProviderClient()
        case .gemini:
            return GeminiCLIProviderClient()
        }
    }
}

private let providerRequestTimeoutSeconds: TimeInterval = 60
private let localDebugResponseDelayNanoseconds: UInt64 = 3_000_000_000
private let localDebugDensificationCharacterLimit = 200
private let densificationSystemInstruction = "You produce concise, complete context with no missing key information."

private func providerWorkLimit(for provider: ProviderName) -> Int {
    DevelopmentConfig.shared.providerParallelWorkLimit(for: provider)
}

private func formattedElapsedSeconds(since startDate: Date) -> String {
    String(format: "%.2f", Date().timeIntervalSince(startDate))
}

actor ProviderWorkLimiter {
    static let shared = ProviderWorkLimiter()
    private var inFlightByProvider: [String: Int] = [:]
    private var waitersByProvider: [String: [CheckedContinuation<Void, Never>]] = [:]

    func acquire(provider: ProviderName, limit: Int) async -> Bool {
        let key = provider.rawValue
        let normalizedLimit = max(1, limit)
        let inFlight = inFlightByProvider[key, default: 0]
        guard inFlight >= normalizedLimit else {
            inFlightByProvider[key] = inFlight + 1
            return false
        }
        await withCheckedContinuation { continuation in
            waitersByProvider[key, default: []].append(continuation)
        }
        return true
    }

    func release(provider: ProviderName) {
        let key = provider.rawValue
        guard var waiters = waitersByProvider[key], !waiters.isEmpty else {
            let nextInFlight = max(0, inFlightByProvider[key, default: 0] - 1)
            if nextInFlight == 0 {
                inFlightByProvider[key] = nil
            } else {
                inFlightByProvider[key] = nextInFlight
            }
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

private func withProviderWorkPermit<T>(
    provider: ProviderName,
    operationName: String,
    _ operation: () async throws -> T
) async throws -> T {
    let limit = providerWorkLimit(for: provider)
    let limiter = ProviderWorkLimiter.shared
    let waited = await limiter.acquire(provider: provider, limit: limit)
    if waited {
        AppLogger.debug(
            "Provider work permit acquired after wait [provider=\(provider.rawValue) operation=\(operationName) limit=\(limit)]"
        )
    }
    do {
        let result = try await operation()
        await limiter.release(provider: provider)
        return result
    } catch {
        await limiter.release(provider: provider)
        throw error
    }
}

private struct CLICommandResult {
    let stdout: String
    let stderr: String
}

private final class CLICommandExecutionState: @unchecked Sendable {
    private let lock = NSLock()
    private var timeoutTriggered = false
    private var continuationResumed = false

    func markTimeoutTriggered() {
        lock.lock()
        timeoutTriggered = true
        lock.unlock()
    }

    func didTimeout() -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return timeoutTriggered
    }

    func markContinuationResumed() -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard !continuationResumed else {
            return false
        }
        continuationResumed = true
        return true
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func promptTextForCLI(_ request: ProviderTextRequest) -> String {
    if
        let systemInstruction = request.systemInstruction?.trimmingCharacters(in: .whitespacesAndNewlines),
        !systemInstruction.isEmpty
    {
        return "\(systemInstruction)\n\n\(request.prompt)"
    }
    return request.prompt
}

private func resolveCLIBinary(for provider: ProviderName) -> String {
    let environment = ProcessInfo.processInfo.environment
    switch provider {
    case .codex:
        return environment["CODEX_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "codex"
    case .claude:
        return environment["CLAUDE_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "claude"
    case .gemini:
        return environment["GEMINI_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "gemini"
    }
}

private func runCLICommand(
    binary: String,
    arguments: [String],
    input: String?,
    timeoutSeconds: TimeInterval = providerRequestTimeoutSeconds
) async throws -> CLICommandResult {
    try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        let executionState = CLICommandExecutionState()

        let resumeOnce: @Sendable (Result<CLICommandResult, Error>) -> Void = { result in
            guard executionState.markContinuationResumed() else {
                return
            }
            continuation.resume(with: result)
        }

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        var processArguments = arguments
        if binary.contains("/") {
            process.executableURL = URL(fileURLWithPath: binary)
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            processArguments.insert(binary, at: 0)
        }
        process.arguments = processArguments

        let timeoutWorkItem = DispatchWorkItem {
            executionState.markTimeoutTriggered()
            if process.isRunning {
                process.terminate()
            }
        }

        process.terminationHandler = { terminatedProcess in
            timeoutWorkItem.cancel()
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let stderrTrimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdoutTrimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)

            if executionState.didTimeout() {
                resumeOnce(
                    .failure(
                        AppError.providerRequestFailed(
                            "CLI command timed out after \(Int(timeoutSeconds)) seconds."
                        )
                    )
                )
                return
            }

            guard terminatedProcess.terminationStatus == 0 else {
                let details = conciseCLIErrorMessage(stderr: stderrTrimmed, stdout: stdoutTrimmed)
                resumeOnce(.failure(AppError.providerRequestFailed(details)))
                return
            }

            resumeOnce(.success(CLICommandResult(stdout: stdout, stderr: stderr)))
        }

        do {
            try process.run()
        } catch {
            resumeOnce(
                .failure(
                    AppError.providerRequestFailed(
                        "Unable to start CLI command \(binary): \(error.localizedDescription)"
                    )
                )
            )
            return
        }

        if
            let input,
            let inputData = input.data(using: .utf8)
        {
            stdinPipe.fileHandleForWriting.write(inputData)
        }
        stdinPipe.fileHandleForWriting.closeFile()

        DispatchQueue.global(qos: .userInitiated)
            .asyncAfter(deadline: .now() + timeoutSeconds, execute: timeoutWorkItem)
    }
}

private func parseJSONPayload(from rawOutput: String) -> [String: Any]? {
    let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }
    if
        trimmed.first == "{",
        let data = trimmed.data(using: .utf8),
        let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
        return payload
    }
    let lines = trimmed
        .split(whereSeparator: \.isNewline)
        .map(String.init)
        .reversed()
    for line in lines {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.first == "{" else {
            continue
        }
        guard
            let data = normalized.data(using: .utf8),
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            continue
        }
        return payload
    }
    return nil
}

private func extractCLIText(from payload: [String: Any]) -> String? {
    let keys = ["result", "response", "output", "message", "text"]
    for key in keys {
        if
            let value = payload[key] as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    return nil
}

private func conciseCLIErrorMessage(stderr: String, stdout: String) -> String {
    if let message = conciseCLIErrorMessage(from: stderr) {
        return message
    }
    if let message = conciseCLIErrorMessage(from: stdout) {
        return message
    }
    return "CLI command failed."
}

private func conciseCLIErrorMessage(from output: String) -> String? {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }
    if
        let payload = parseJSONPayload(from: trimmed),
        let message = extractCLIErrorMessage(from: payload)
    {
        return message
    }
    let lines = trimmed
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    for line in lines {
        if let normalized = normalizedCLIErrorLine(line) {
            return normalized
        }
    }
    for line in lines where !shouldSkipCLIErrorLine(line) {
        guard line != "{", line != "}" else {
            continue
        }
        return line
    }
    return nil
}

private func extractCLIErrorMessage(from payload: [String: Any]) -> String? {
    if
        let nestedError = payload["error"] as? [String: Any],
        let message = normalizedCLIErrorText(nestedError["message"] as? String)
    {
        return message
    }
    if
        let nestedError = payload["error"] as? [String: Any],
        let type = normalizedCLIErrorText(nestedError["type"] as? String),
        type.lowercased() != "error"
    {
        return type
    }
    if let message = normalizedCLIErrorText(payload["message"] as? String) {
        return message
    }
    if let message = normalizedCLIErrorText(payload["error"] as? String) {
        return message
    }
    return nil
}

private func normalizedCLIErrorText(_ text: String?) -> String? {
    guard var normalized = text?.trimmingCharacters(in: .whitespacesAndNewlines) else {
        return nil
    }
    guard !normalized.isEmpty, normalized != "[object Object]" else {
        return nil
    }
    if let range = normalized.range(of: #"^[A-Za-z0-9_]+Error:\s*"#, options: .regularExpression) {
        normalized.removeSubrange(range)
    }
    normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
}

private func normalizedCLIErrorLine(_ line: String) -> String? {
    guard !shouldSkipCLIErrorLine(line) else {
        return nil
    }
    if let range = line.range(of: #"[A-Za-z0-9_]+Error:\s*"#, options: .regularExpression) {
        let suffix = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !suffix.isEmpty {
            return suffix
        }
    }
    let signal = line.lowercased()
    if signal.contains("requested entity was not found")
        || signal.contains("rate limit")
        || signal.contains("token limit")
        || signal.contains("context window")
        || signal.contains("maximum context length")
    {
        return line
    }
    return nil
}

private func shouldSkipCLIErrorLine(_ line: String) -> Bool {
    let signal = line.lowercased()
    return signal.hasPrefix("at ")
        || signal.contains("file:///")
        || signal.contains("node:internal/")
        || signal.contains("loaded cached credentials.")
}

private func densificationPrompt(for request: DensificationRequest) -> String {
    [
        "Extract essential context from captured UI text.",
        "App: \(request.appName)",
        "Window: \(request.windowTitle)",
        "",
        request.inputText
    ].joined(separator: "\n")
}

private func localDebugPrefixText(_ value: String, maxCharacters: Int) -> String {
    String(value.prefix(maxCharacters))
}

private struct CodexCLIProviderClient: ProviderClient {
    let provider: ProviderName = .codex

    func requestText(request: ProviderTextRequest, apiKey: String, model: String) async throws -> String {
        try await withProviderWorkPermit(provider: provider, operationName: "request_text") {
            let prompt = promptTextForCLI(request)
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("contextbrief-codex-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(at: temporaryDirectory)
            }
            let outputPath = temporaryDirectory.appendingPathComponent("last-message.txt")

            var arguments = [
                "exec",
                "--skip-git-repo-check",
                "--json",
                "--output-last-message", outputPath.path,
                "--ask-for-approval", "never",
                "--sandbox", "read-only",
                "-"
            ]
            let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedModel.isEmpty {
                arguments.insert(contentsOf: ["-m", normalizedModel], at: 1)
            }

            let result = try await runCLICommand(
                binary: resolveCLIBinary(for: provider),
                arguments: arguments,
                input: prompt
            )

            if
                let fileText = try? String(contentsOf: outputPath, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                !fileText.isEmpty
            {
                return fileText
            }

            if
                let payload = parseJSONPayload(from: result.stdout),
                let jsonText = extractCLIText(from: payload)
            {
                return jsonText
            }
            guard let fallback = result.stdout.nonEmpty else {
                throw AppError.providerRequestFailed("Codex CLI returned an empty response.")
            }
            return fallback
        }
    }
}

private struct ClaudeCLIProviderClient: ProviderClient {
    let provider: ProviderName = .claude

    func requestText(request: ProviderTextRequest, apiKey: String, model: String) async throws -> String {
        try await withProviderWorkPermit(provider: provider, operationName: "request_text") {
            let prompt = promptTextForCLI(request)
            var arguments = [
                "-p", prompt,
                "--output-format", "json"
            ]
            let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedModel.isEmpty {
                arguments.append(contentsOf: ["--model", normalizedModel])
            }
            let result = try await runCLICommand(
                binary: resolveCLIBinary(for: provider),
                arguments: arguments,
                input: nil
            )
            if
                let payload = parseJSONPayload(from: result.stdout),
                let text = extractCLIText(from: payload)
            {
                return text
            }
            guard let fallback = result.stdout.nonEmpty else {
                throw AppError.providerRequestFailed("Claude CLI returned an empty response.")
            }
            return fallback
        }
    }
}

private struct GeminiCLIProviderClient: ProviderClient {
    let provider: ProviderName = .gemini

    func requestText(request: ProviderTextRequest, apiKey: String, model: String) async throws -> String {
        try await withProviderWorkPermit(provider: provider, operationName: "request_text") {
            let prompt = promptTextForCLI(request)
            let normalizedModel = normalizedGeminiCLIModel(model)
            return try await runGeminiCommand(prompt: prompt, model: normalizedModel)
        }
    }

    private func runGeminiCommand(prompt: String, model: String) async throws -> String {
        var arguments = [
            "--output-format", "json",
            "--prompt", prompt
        ]
        if !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        let result = try await runCLICommand(
            binary: resolveCLIBinary(for: provider),
            arguments: arguments,
            input: nil
        )
        if
            let payload = parseJSONPayload(from: result.stdout),
            let text = extractCLIText(from: payload)
        {
            return text
        }
        guard let fallback = result.stdout.nonEmpty else {
            throw AppError.providerRequestFailed("Gemini CLI returned an empty response.")
        }
        return fallback
    }
}

private func normalizedGeminiCLIModel(_ model: String) -> String {
    let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
    switch normalizedModel {
    case "gemini-flash-latest":
        return "gemini-2.5-flash"
    default:
        return normalizedModel
    }
}
