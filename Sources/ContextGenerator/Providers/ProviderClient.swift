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

public struct DensificationResult {
    public let content: String
    public let title: String?

    public init(content: String, title: String?) {
        self.content = content
        self.title = title
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
    func requestText(request: ProviderTextRequest, model: String) async throws -> String
    func densify(request: DensificationRequest, model: String) async throws -> DensificationResult
    func requestDensification(request: DensificationRequest, model: String) async throws -> DensificationResult
}

public extension ProviderClient {
    func densify(request: DensificationRequest, model: String) async throws -> DensificationResult {
        let startedAt = Date()
        try await forceFailure()
        if DevelopmentConfig.shared.localDebugResponsesEnabled {
            AppLogger.debug("Local debug response enabled.")
            try await Task.sleep(nanoseconds: localDebugResponseDelayNanoseconds)
            let output = localDebugPrefixText(request.inputText, maxCharacters: localDebugDensificationCharacterLimit)
            AppLogger.debug(
                "Densification completed [provider=\(provider.rawValue) runs=1 seconds=\(formattedElapsedSeconds(since: startedAt))]"
            )
            return DensificationResult(content: output, title: nil)
        }
        let result = try await requestDensification(request: request, model: model)
        AppLogger.debug(
            "Densification completed [provider=\(provider.rawValue) runs=1 seconds=\(formattedElapsedSeconds(since: startedAt))]"
        )
        return result
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
            throw AppError.providerRequestTransientFailure("Forced provider failure for debugging.")
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
private let providerRequestOverallTimeoutSeconds: TimeInterval = 90
private let providerRequestMaxAttempts = 3
private let providerRetryBaseDelayNanoseconds: UInt64 = 400_000_000
private let providerRetryMaxDelayNanoseconds: UInt64 = 2_000_000_000
private let localDebugResponseDelayNanoseconds: UInt64 = 3_000_000_000
private let localDebugDensificationCharacterLimit = 200
private let maxCLIPromptCharacters = 800_000
private let maxCLIResponseCharacters = 200_000
private let maxCLIErrorSnippetCharacters = 600
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

private func logCLIResponse(
    provider: ProviderName,
    binary: String,
    exitStatus: Int32,
    timedOut: Bool,
    stdout: String,
    stderr: String
) {
    let statusLabel = timedOut ? "timeout" : "exit \(exitStatus)"
    let headline = "CLI response provider=\(provider.rawValue) binary=\(binary) \(statusLabel)"
    let body = [
        "stdout (\(stdout.count) chars):",
        stdout.isEmpty ? "(empty)" : stdout,
        "",
        "stderr (\(stderr.count) chars):",
        stderr.isEmpty ? "(empty)" : stderr
    ].joined(separator: "\n")
    AppLogger.filePrintMultiline(level: "DEBUG", headline: headline, body: body)
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

private func validatedPromptTextForCLI(_ request: ProviderTextRequest, provider: ProviderName) throws -> String {
    let prompt = promptTextForCLI(request)
    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw AppError.providerRequestRejected("\(provider.rawValue.capitalized) CLI prompt is empty.")
    }
    guard trimmed.count <= maxCLIPromptCharacters else {
        throw AppError.providerRequestRejected(
            "\(provider.rawValue.capitalized) CLI prompt is too large (\(trimmed.count) characters)."
        )
    }
    return trimmed
}

private func normalizedCLIModel(for provider: ProviderName, rawModel: String) throws -> String {
    let normalized = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
        throw AppError.providerRequestRejected("Missing model id for \(provider.rawValue).")
    }
    return normalized
}

private func orderedUnique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var ordered: [String] = []
    for value in values {
        guard !value.isEmpty else {
            continue
        }
        let key = value.lowercased()
        guard !seen.contains(key) else {
            continue
        }
        seen.insert(key)
        ordered.append(value)
    }
    return ordered
}

private func geminiFallbackModelCandidates(for model: String) -> [String] {
    guard !model.isEmpty else {
        return [""]
    }
    let lower = model.lowercased()
    var candidates = [model]
    if lower.hasSuffix("-preview") {
        candidates.append(String(model.dropLast("-preview".count)))
    }
    if let expRange = lower.range(of: "-exp") {
        candidates.append(String(model[..<expRange.lowerBound]))
    }
    if lower.contains("gemini-3") {
        if lower.contains("flash") {
            candidates.append("gemini-2.5-flash")
        } else if lower.contains("pro") {
            candidates.append("gemini-2.5-pro")
        } else {
            candidates.append("gemini-2.5-flash")
        }
    }
    if lower.contains("flash") {
        candidates.append("gemini-2.5-flash")
    }
    return orderedUnique(candidates)
}

private func suggestedModels(for provider: ProviderName, requestedModel: String) -> [String] {
    switch provider {
    case .gemini:
        let normalizedRequestedModel = requestedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedRequestedModel.isEmpty || normalizedRequestedModel == "selected model" {
            return ["gemini-2.5-flash", "gemini-2.5-pro"]
        }
        return orderedUnique(geminiFallbackModelCandidates(for: normalizedRequestedModel).prefix(3).map { $0 })
    case .codex:
        return ["gpt-5", "gpt-5-mini"]
    case .claude:
        return ["sonnet", "opus"]
    }
}

private func normalizedCLIResponseText(_ value: String, provider: ProviderName) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw AppError.providerRequestTransientFailure("\(provider.rawValue.capitalized) CLI returned an empty response.")
    }
    if trimmed.count <= maxCLIResponseCharacters {
        return trimmed
    }
    AppLogger.debug(
        "\(provider.rawValue.capitalized) CLI response exceeded \(maxCLIResponseCharacters) characters and was truncated."
    )
    return String(trimmed.prefix(maxCLIResponseCharacters))
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
    provider: ProviderName,
    binary: String,
    arguments: [String],
    input: String?,
    model: String?,
    timeoutSeconds: TimeInterval = providerRequestTimeoutSeconds,
    environmentOverrides: [String: String] = [:]
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
        if !environmentOverrides.isEmpty {
            var mergedEnvironment = ProcessInfo.processInfo.environment
            for (key, value) in environmentOverrides {
                mergedEnvironment[key] = value
            }
            process.environment = mergedEnvironment
        }

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
            let timedOut = executionState.didTimeout()

            logCLIResponse(
                provider: provider,
                binary: binary,
                exitStatus: terminatedProcess.terminationStatus,
                timedOut: timedOut,
                stdout: stdout,
                stderr: stderr
            )

            if timedOut {
                resumeOnce(
                    .failure(
                        AppError.providerRequestTimedOut(
                            provider: provider,
                            timeoutSeconds: max(1, Int(timeoutSeconds.rounded()))
                        )
                    )
                )
                return
            }

            guard terminatedProcess.terminationStatus == 0 else {
                let details = conciseCLIErrorMessage(stderr: stderrTrimmed, stdout: stdoutTrimmed)
                resumeOnce(
                    .failure(
                        classifyCLIProcessFailure(
                            provider: provider,
                            binary: binary,
                            model: model,
                            details: details
                        )
                    )
                )
                return
            }

            resumeOnce(.success(CLICommandResult(stdout: stdout, stderr: stderr)))
        }

        do {
            try process.run()
        } catch {
            AppLogger.filePrintMultiline(
                level: "DEBUG",
                headline: "CLI response provider=\(provider.rawValue) binary=\(binary) failed to start",
                body: "error: \(error.localizedDescription)"
            )
            resumeOnce(
                .failure(classifyCLIStartupFailure(provider: provider, binary: binary, error: error))
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

private func boundedSnippet(_ value: String, maxCharacters: Int) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > maxCharacters else {
        return trimmed
    }
    return String(trimmed.prefix(maxCharacters))
}

private func containsAnySignal(_ value: String, signals: [String]) -> Bool {
    signals.contains { value.contains($0) }
}

private func isAuthenticationSignal(_ signal: String) -> Bool {
    containsAnySignal(
        signal,
        signals: [
            "auth",
            "unauthorized",
            "forbidden",
            "invalid api key",
            "not logged in",
            "login required",
            "permission denied"
        ]
    )
}

private func isModelUnavailableSignal(_ signal: String) -> Bool {
    containsAnySignal(
        signal,
        signals: [
            "model not found",
            "unknown model",
            "invalid model",
            "requested entity was not found",
            "unsupported model",
            "not available"
        ]
    )
}

private func isTransientCLIErrorSignal(_ signal: String) -> Bool {
    containsAnySignal(
        signal,
        signals: [
            "timed out",
            "timeout",
            "rate limit",
            "temporarily unavailable",
            "econnreset",
            "etimedout",
            "eai_again",
            "connection reset",
            "503",
            "502",
            "429",
            "empty response"
        ]
    )
}

private func isCLIUsageSignal(_ signal: String) -> Bool {
    containsAnySignal(
        signal,
        signals: [
            "unknown option",
            "invalid option",
            "usage:",
            "unexpected argument",
            "requires an argument"
        ]
    )
}

private func isBinaryMissingSignal(_ signal: String) -> Bool {
    containsAnySignal(
        signal,
        signals: [
            "command not found",
            "no such file or directory",
            "could not find executable"
        ]
    )
}

private func classifyCLIStartupFailure(provider: ProviderName, binary: String, error: Error) -> AppError {
    let details = boundedSnippet(error.localizedDescription, maxCharacters: maxCLIErrorSnippetCharacters)
    let signal = details.lowercased()
    if isBinaryMissingSignal(signal) {
        return AppError.providerBinaryNotFound(provider: provider, binary: binary)
    }
    return AppError.providerRequestRejected(
        "Unable to start \(provider.rawValue.capitalized) CLI command (\(binary)): \(details)"
    )
}

private func classifyCLIProcessFailure(
    provider: ProviderName,
    binary: String,
    model: String?,
    details: String
) -> AppError {
    let boundedDetails = boundedSnippet(details, maxCharacters: maxCLIErrorSnippetCharacters)
    let signal = boundedDetails.lowercased()
    if isBinaryMissingSignal(signal) {
        return AppError.providerBinaryNotFound(provider: provider, binary: binary)
    }
    if isAuthenticationSignal(signal) {
        return AppError.providerAuthenticationFailed(provider: provider, details: boundedDetails)
    }
    if isModelUnavailableSignal(signal) {
        let requestedModel = (model?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty) ?? "selected model"
        return AppError.providerModelUnavailable(
            provider: provider,
            model: requestedModel,
            suggestions: suggestedModels(for: provider, requestedModel: requestedModel)
        )
    }
    if isTransientCLIErrorSignal(signal) {
        return AppError.providerRequestTransientFailure(boundedDetails)
    }
    if isCLIUsageSignal(signal) {
        return AppError.providerRequestRejected(boundedDetails)
    }
    return AppError.providerRequestRejected(boundedDetails)
}

private func isRetryableProviderRequestError(_ error: Error) -> Bool {
    guard let appError = error as? AppError else {
        return false
    }
    return appError.isRetryableProviderFailure
}

private func retryDelayNanoseconds(forAttempt attempt: Int) -> UInt64 {
    let exponent = max(0, attempt - 1)
    let multiplier = UInt64(1 << min(exponent, 10))
    let baseDelay = min(providerRetryMaxDelayNanoseconds, providerRetryBaseDelayNanoseconds * multiplier)
    let jitter = UInt64.random(in: 0 ... 250_000_000)
    return min(providerRetryMaxDelayNanoseconds, baseDelay + jitter)
}

private func withRetriedProviderRequest<T>(
    provider: ProviderName,
    model: String,
    _ operation: (_ timeoutSeconds: TimeInterval) async throws -> T
) async throws -> T {
    let startedAt = Date()
    var attempt = 1
    var lastError: Error?
    while attempt <= providerRequestMaxAttempts {
        let elapsed = Date().timeIntervalSince(startedAt)
        let remaining = providerRequestOverallTimeoutSeconds - elapsed
        if remaining <= 0 {
            throw AppError.providerRequestTimedOut(
                provider: provider,
                timeoutSeconds: Int(providerRequestOverallTimeoutSeconds)
            )
        }
        let attemptTimeout = max(1, min(providerRequestTimeoutSeconds, remaining))
        do {
            return try await operation(attemptTimeout)
        } catch {
            if error is CancellationError {
                throw error
            }
            lastError = error
            guard attempt < providerRequestMaxAttempts, isRetryableProviderRequestError(error) else {
                throw error
            }
            let remainingAfterFailure = providerRequestOverallTimeoutSeconds - Date().timeIntervalSince(startedAt)
            if remainingAfterFailure <= 0 {
                break
            }
            let maxDelaySeconds = max(0, remainingAfterFailure - 0.05)
            let cappedDelay = min(
                retryDelayNanoseconds(forAttempt: attempt),
                UInt64(maxDelaySeconds * 1_000_000_000)
            )
            if cappedDelay == 0 {
                break
            }
            AppLogger.debug(
                "Retrying provider request [provider=\(provider.rawValue) model=\(model.isEmpty ? "default" : model) attempt=\(attempt + 1)/\(providerRequestMaxAttempts)]"
            )
            do {
                try await Task.sleep(nanoseconds: cappedDelay)
            } catch {
                throw error
            }
            attempt += 1
        }
    }
    if let appError = lastError as? AppError {
        throw appError
    }
    throw AppError.providerRequestTransientFailure("\(provider.rawValue.capitalized) CLI request failed.")
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
    let keys = ["content", "result", "response", "output", "message", "text"]
    let source = (payload["structured_output"] as? [String: Any]) ?? payload
    for key in keys {
        if
            let value = source[key] as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    return nil
}

private func extractCLITitle(from payload: [String: Any]) -> String? {
    let source: String? = (payload["structured_output"] as? [String: Any])?["title"] as? String
        ?? payload["title"] as? String
    guard
        let value = source,
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
        return nil
    }
    return String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
}

private func conciseCLIErrorMessage(stderr: String, stdout: String) -> String {
    if let message = conciseCLIErrorMessage(from: stderr) {
        return boundedSnippet(message, maxCharacters: maxCLIErrorSnippetCharacters)
    }
    if let message = conciseCLIErrorMessage(from: stdout) {
        return boundedSnippet(message, maxCharacters: maxCLIErrorSnippetCharacters)
    }
    return boundedSnippet("CLI command failed.", maxCharacters: maxCLIErrorSnippetCharacters)
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
        if let message = extractMessageFromErrorPrefixedLine(line) {
            return message
        }
    }
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

private func extractMessageFromErrorPrefixedLine(_ line: String) -> String? {
    let lower = line.lowercased()
    let prefix = lower.hasPrefix("error: ") ? "error: " : (lower.hasPrefix("error:") ? "error:" : nil)
    guard let prefix else { return nil }
    let rest = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    guard rest.first == "{", let data = rest.data(using: .utf8),
          let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let message = extractCLIErrorMessage(from: payload) else {
        return nil
    }
    return message
}

private func isClaudeErrorPayload(_ payload: [String: Any]) -> Bool {
    (payload["is_error"] as? NSNumber)?.boolValue ?? (payload["is_error"] as? Bool) ?? false
}

private func claudeErrorMessageIfError(from payload: [String: Any]) -> String? {
    guard isClaudeErrorPayload(payload) else { return nil }
    return (payload["result"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        ?? "Claude CLI returned an error."
}

private func extractCLIErrorMessage(from payload: [String: Any]) -> String? {
    if let message = claudeErrorMessageIfError(from: payload) {
        return message
    }
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
    if let message = normalizedCLIErrorText(payload["detail"] as? String) {
        return message
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

private let densificationJSONSchema = """
{"type":"object","properties":{"content":{"type":"string","description":"Densified extract of the captured UI text"},"title":{"type":"string","description":"Short title for the snapshot, max 6 words"}},"required":["content","title"],"additionalProperties":false}
"""

private func densificationPrompt(for request: DensificationRequest) -> String {
    [
        "Extract essential context from captured UI text.",
        "Also provide a short title (max 6 words) for this snapshot.",
        "Respond with a JSON object with two fields: \"content\" (the densified text) and \"title\" (the short title).",
        "",
        "App: \(request.appName)",
        "Window: \(request.windowTitle)",
        "",
        request.inputText
    ].joined(separator: "\n")
}

private func densificationPromptForStructuredOutput(for request: DensificationRequest) -> String {
    [
        "Extract essential context from captured UI text.",
        "Provide a short title (max 6 words) for this snapshot.",
        "",
        "App: \(request.appName)",
        "Window: \(request.windowTitle)",
        "",
        request.inputText
    ].joined(separator: "\n")
}

private func localDebugPrefixText(_ value: String, maxCharacters: Int) -> String {
    String(value.prefix(maxCharacters))
}

private func logDensificationRawOutput(raw: String) {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    if
        let payload = parseJSONPayload(from: trimmed),
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
        let pretty = String(data: data, encoding: .utf8)
    {
        AppLogger.filePrintMultiline(level: "DEBUG", headline: "Densification raw response (JSON):", body: pretty)
    } else {
        AppLogger.filePrintMultiline(level: "DEBUG", headline: "Densification raw response:", body: trimmed)
    }
}

private func parseJsonFromOutput(_ output: String) -> [String: Any]? {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.first == "{" {
        return parseJSONPayload(from: trimmed)
    }
    if let range = trimmed.range(of: "\n{", options: .backwards) {
        let fromBrace = trimmed.index(range.lowerBound, offsetBy: 1)
        var candidate = String(trimmed[fromBrace...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasSuffix("```") {
            candidate = String(candidate.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if candidate.hasSuffix("\n```") {
            candidate = String(candidate.dropLast(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return parseJSONPayload(from: candidate)
    }
    return nil
}

private func extractDensificationFromEmbeddedString(_ raw: String) -> (content: String, title: String?)? {
    guard let payload = parseJsonFromOutput(raw) else { return nil }
    let content = extractCLIText(from: payload) ?? ""
    let title = extractCLITitle(from: payload)
    return content.isEmpty ? nil : (content, title)
}

private func parseDensificationResponse(stdout: String, fileContent: String? = nil) -> DensificationResult {
    let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedFile = fileContent?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    let source = trimmedFile ?? trimmedStdout
    logDensificationRawOutput(raw: source)
    let fallbackContent = (trimmedFile ?? trimmedStdout).isEmpty ? "" : (trimmedFile ?? trimmedStdout)
    if let payload = parseJSONPayload(from: source), !source.isEmpty {
        var content = extractCLIText(from: payload) ?? fallbackContent
        var title = extractCLITitle(from: payload)
        if title == nil, !content.isEmpty, let inner = extractDensificationFromEmbeddedString(content) {
            content = inner.content
            title = inner.title
        }
        return DensificationResult(
            content: content.isEmpty ? fallbackContent : content,
            title: title
        )
    }
    if let payload = parseJSONPayload(from: trimmedStdout) {
        var content = extractCLIText(from: payload) ?? fallbackContent
        var title = extractCLITitle(from: payload)
        if title == nil, !content.isEmpty, let inner = extractDensificationFromEmbeddedString(content) {
            content = inner.content
            title = inner.title
        }
        return DensificationResult(
            content: content.isEmpty ? fallbackContent : content,
            title: title
        )
    }
    return DensificationResult(content: fallbackContent, title: nil)
}

private struct CodexCLIProviderClient: ProviderClient {
    let provider: ProviderName = .codex

    func requestText(request: ProviderTextRequest, model: String) async throws -> String {
        let prompt = try validatedPromptTextForCLI(request, provider: provider)
        let normalizedModel = try normalizedCLIModel(for: provider, rawModel: model)
        let binary = resolveCLIBinary(for: provider)
        return try await withRetriedProviderRequest(provider: provider, model: normalizedModel) { timeoutSeconds in
            try await withProviderWorkPermit(provider: provider, operationName: "request_text") {
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
                    "--output-last-message", outputPath.path,
                    "-c", "ask_for_approval=never",
                    "--sandbox", "read-only",
                    "-"
                ]
                if !normalizedModel.isEmpty {
                    arguments.insert(contentsOf: ["-m", normalizedModel], at: 1)
                }

                let result = try await runCLICommand(
                    provider: provider,
                    binary: binary,
                    arguments: arguments,
                    input: prompt,
                    model: normalizedModel.nonEmpty,
                    timeoutSeconds: timeoutSeconds
                )

                if let fileText = try? String(contentsOf: outputPath, encoding: .utf8), !fileText.isEmpty {
                    return try normalizedCLIResponseText(fileText, provider: provider)
                }

                if
                    let payload = parseJSONPayload(from: result.stdout),
                    let jsonText = extractCLIText(from: payload)
                {
                    return try normalizedCLIResponseText(jsonText, provider: provider)
                }
                return try normalizedCLIResponseText(result.stdout, provider: provider)
            }
        }
    }

    func requestDensification(request: DensificationRequest, model: String) async throws -> DensificationResult {
        let textRequest = ProviderTextRequest(
            systemInstruction: densificationSystemInstruction,
            prompt: densificationPromptForStructuredOutput(for: request)
        )
        let prompt = try validatedPromptTextForCLI(textRequest, provider: provider)
        let normalizedModel = try normalizedCLIModel(for: provider, rawModel: model)
        let binary = resolveCLIBinary(for: provider)
        return try await withRetriedProviderRequest(provider: provider, model: normalizedModel) { timeoutSeconds in
            try await withProviderWorkPermit(provider: provider, operationName: "request_densification") {
                let temporaryDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("contextbrief-codex-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
                defer {
                    try? FileManager.default.removeItem(at: temporaryDirectory)
                }
                let outputPath = temporaryDirectory.appendingPathComponent("last-message.txt")
                let schemaPath = temporaryDirectory.appendingPathComponent("densify-schema.json")
                try densificationJSONSchema.write(to: schemaPath, atomically: true, encoding: .utf8)
                var arguments = [
                    "exec",
                    "--skip-git-repo-check",
                    "--json",
                    "--output-schema", schemaPath.path,
                    "--output-last-message", outputPath.path,
                    "-c", "ask_for_approval=never",
                    "--sandbox", "read-only",
                    "-"
                ]
                if !normalizedModel.isEmpty {
                    arguments.insert(contentsOf: ["-m", normalizedModel], at: 1)
                }
                let result = try await runCLICommand(
                    provider: provider,
                    binary: binary,
                    arguments: arguments,
                    input: prompt,
                    model: normalizedModel.nonEmpty,
                    timeoutSeconds: timeoutSeconds
                )
                let fileText = try? String(contentsOf: outputPath, encoding: .utf8)
                let parsed = parseDensificationResponse(stdout: result.stdout, fileContent: fileText)
                let content = try normalizedCLIResponseText(parsed.content, provider: provider)
                return DensificationResult(content: content, title: parsed.title)
            }
        }
    }
}

private struct ClaudeCLIProviderClient: ProviderClient {
    let provider: ProviderName = .claude

    func requestText(request: ProviderTextRequest, model: String) async throws -> String {
        let prompt = try validatedPromptTextForCLI(request, provider: provider)
        let normalizedModel = try normalizedCLIModel(for: provider, rawModel: model)
        let binary = resolveCLIBinary(for: provider)
        return try await withRetriedProviderRequest(provider: provider, model: normalizedModel) { timeoutSeconds in
            try await withProviderWorkPermit(provider: provider, operationName: "request_text") {
                var arguments = [
                    "-p", prompt,
                    "--output-format", "json"
                ]
                if !normalizedModel.isEmpty {
                    arguments.append(contentsOf: ["--model", normalizedModel])
                }
                let result = try await runCLICommand(
                    provider: provider,
                    binary: binary,
                    arguments: arguments,
                    input: nil,
                    model: normalizedModel.nonEmpty,
                    timeoutSeconds: timeoutSeconds
                )
                if let payload = parseJSONPayload(from: result.stdout) {
                    if let message = claudeErrorMessageIfError(from: payload) {
                        throw AppError.providerRequestRejected(message)
                    }
                    if let text = extractCLIText(from: payload) {
                        return try normalizedCLIResponseText(text, provider: provider)
                    }
                }
                return try normalizedCLIResponseText(result.stdout, provider: provider)
            }
        }
    }

    func requestDensification(request: DensificationRequest, model: String) async throws -> DensificationResult {
        let textRequest = ProviderTextRequest(
            systemInstruction: densificationSystemInstruction,
            prompt: densificationPromptForStructuredOutput(for: request)
        )
        let prompt = try validatedPromptTextForCLI(textRequest, provider: provider)
        let normalizedModel = try normalizedCLIModel(for: provider, rawModel: model)
        let binary = resolveCLIBinary(for: provider)
        return try await withRetriedProviderRequest(provider: provider, model: normalizedModel) { timeoutSeconds in
            try await withProviderWorkPermit(provider: provider, operationName: "request_densification") {
                var arguments = [
                    "-p", prompt,
                    "--output-format", "json",
                    "--json-schema", densificationJSONSchema
                ]
                if !normalizedModel.isEmpty {
                    arguments.append(contentsOf: ["--model", normalizedModel])
                }
                let result = try await runCLICommand(
                    provider: provider,
                    binary: binary,
                    arguments: arguments,
                    input: nil,
                    model: normalizedModel.nonEmpty,
                    timeoutSeconds: timeoutSeconds
                )
                if let payload = parseJSONPayload(from: result.stdout),
                   let message = claudeErrorMessageIfError(from: payload)
                {
                    throw AppError.providerRequestRejected(message)
                }
                let parsed = parseDensificationResponse(stdout: result.stdout)
                let content = try normalizedCLIResponseText(parsed.content, provider: provider)
                return DensificationResult(content: content, title: parsed.title)
            }
        }
    }
}

private struct GeminiCLIProviderClient: ProviderClient {
    let provider: ProviderName = .gemini

    func requestText(request: ProviderTextRequest, model: String) async throws -> String {
        let prompt = try validatedPromptTextForCLI(request, provider: provider)
        let normalizedModel = try normalizedCLIModel(for: provider, rawModel: model)
        let binary = resolveCLIBinary(for: provider)
        let candidateModels = geminiFallbackModelCandidates(for: normalizedModel)
        let retryLabel = normalizedModel.nonEmpty ?? "default"
        return try await withRetriedProviderRequest(provider: provider, model: retryLabel) { timeoutSeconds in
            try await withProviderWorkPermit(provider: provider, operationName: "request_text") {
                var lastError: Error?
                for candidate in candidateModels {
                    do {
                        return try await runGeminiCommand(
                            prompt: prompt,
                            model: candidate,
                            binary: binary,
                            timeoutSeconds: timeoutSeconds
                        )
                    } catch {
                        lastError = error
                        guard shouldFallbackGeminiModel(after: error) else {
                            throw error
                        }
                        AppLogger.debug(
                            "Gemini model fallback [requested=\(retryLabel) fallback=\(candidate)]"
                        )
                    }
                }
                if let appError = lastError as? AppError {
                    throw appError
                }
                throw AppError.providerRequestRejected("Gemini CLI request failed.")
            }
        }
    }

    private func runGeminiCommand(
        prompt: String,
        model: String,
        binary: String,
        timeoutSeconds: TimeInterval
    ) async throws -> String {
        var arguments = [
            "--output-format", "json",
            "--prompt", prompt
        ]
        if !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        let result = try await runCLICommand(
            provider: provider,
            binary: binary,
            arguments: arguments,
            input: nil,
            model: model.nonEmpty,
            timeoutSeconds: timeoutSeconds,
            environmentOverrides: resolvedGeminiEnvironmentOverrides()
        )
        if
            let payload = parseJSONPayload(from: result.stdout),
            let text = extractCLIText(from: payload)
        {
            return try normalizedCLIResponseText(text, provider: provider)
        }
        return try normalizedCLIResponseText(result.stdout, provider: provider)
    }

    func requestDensification(request: DensificationRequest, model: String) async throws -> DensificationResult {
        let textRequest = ProviderTextRequest(
            systemInstruction: densificationSystemInstruction,
            prompt: densificationPrompt(for: request)
        )
        let prompt = try validatedPromptTextForCLI(textRequest, provider: provider)
        let normalizedModel = try normalizedCLIModel(for: provider, rawModel: model)
        let binary = resolveCLIBinary(for: provider)
        let candidateModels = geminiFallbackModelCandidates(for: normalizedModel)
        let retryLabel = normalizedModel.nonEmpty ?? "default"
        return try await withRetriedProviderRequest(provider: provider, model: retryLabel) { timeoutSeconds in
            try await withProviderWorkPermit(provider: provider, operationName: "request_densification") {
                var lastError: Error?
                for candidate in candidateModels {
                    do {
                        let stdout = try await runGeminiCommandRaw(
                            prompt: prompt,
                            model: candidate,
                            binary: binary,
                            timeoutSeconds: timeoutSeconds
                        )
                        let parsed = parseDensificationResponse(stdout: stdout)
                        let content = try normalizedCLIResponseText(parsed.content, provider: provider)
                        return DensificationResult(content: content, title: parsed.title)
                    } catch {
                        lastError = error
                        guard shouldFallbackGeminiModel(after: error) else {
                            throw error
                        }
                        AppLogger.debug(
                            "Gemini model fallback [requested=\(retryLabel) fallback=\(candidate)]"
                        )
                    }
                }
                if let appError = lastError as? AppError {
                    throw appError
                }
                throw AppError.providerRequestRejected("Gemini CLI request failed.")
            }
        }
    }

    private func runGeminiCommandRaw(
        prompt: String,
        model: String,
        binary: String,
        timeoutSeconds: TimeInterval
    ) async throws -> String {
        var arguments = [
            "--output-format", "json",
            "--prompt", prompt
        ]
        if !model.isEmpty {
            arguments.append(contentsOf: ["--model", model])
        }
        let result = try await runCLICommand(
            provider: provider,
            binary: binary,
            arguments: arguments,
            input: nil,
            model: model.nonEmpty,
            timeoutSeconds: timeoutSeconds,
            environmentOverrides: resolvedGeminiEnvironmentOverrides()
        )
        return result.stdout
    }
}

private func shouldFallbackGeminiModel(after error: Error) -> Bool {
    guard let appError = error as? AppError else {
        return false
    }
    switch appError {
    case .providerModelUnavailable(let provider, _, _):
        return provider == .gemini
    default:
        return false
    }
}

private func resolvedGeminiEnvironmentOverrides() -> [String: String] {
    let environment = ProcessInfo.processInfo.environment
    guard environment["GEMINI_CLI_NO_RELAUNCH"]?.nonEmpty == nil else {
        return [:]
    }
    return ["GEMINI_CLI_NO_RELAUNCH": "true"]
}
