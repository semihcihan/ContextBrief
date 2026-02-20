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
                "Densification completed [provider=\(provider.rawValue) runs=1 chunked=false seconds=\(formattedElapsedSeconds(since: startedAt))]"
            )
            return output
        }
        do {
            let output = try await requestText(
                request: ProviderTextRequest(
                    systemInstruction: densificationSystemInstruction,
                    prompt: densificationPrompt(for: request)
                ),
                apiKey: apiKey,
                model: model
            )
            AppLogger.debug(
                "Densification completed [provider=\(provider.rawValue) runs=1 chunked=false seconds=\(formattedElapsedSeconds(since: startedAt))]"
            )
            return output
        } catch {
            guard isContextWindowExceededError(error) else {
                throw error
            }
            AppLogger.debug(
                "Densification exceeded \(provider.rawValue) context window. Retrying with chunking fallback."
            )
            let stats = DensificationDebugStats()
            let output = try await densifyWithAdaptiveChunking(
                request: request,
                apiKey: apiKey,
                model: model,
                contextWindowTokens: reactiveContextWindowTokenLimit,
                stats: stats
            )
            AppLogger.debug(
                "Densification completed [provider=\(provider.rawValue) runs=\(stats.runCount) chunked=true seconds=\(formattedElapsedSeconds(since: startedAt))]"
            )
            return output
        }
    }
}

private final class DensificationDebugStats {
    var runCount = 0
}

private struct DensificationBudgetPlan {
    let contextWindowTokens: Int
    let chunkInputTokens: Int
    let initialMergeInputTokens: Int
    let chunkTargetWordLimit: Int
    let mergeTargetWordLimit: Int
    let outputReserveTokens: Int
    let safetyMarginTokens: Int
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

    func initialChunkInputBudget(
        request: DensificationRequest,
        contextWindowTokens: Int
    ) -> Int {
        makeDensificationBudgetPlan(
            request: request,
            contextWindowTokens: contextWindowTokens,
            requestedChunkInputTokens: contextWindowTokens
        ).chunkInputTokens
    }

    func makeDensificationBudgetPlan(
        request: DensificationRequest,
        contextWindowTokens: Int,
        requestedChunkInputTokens: Int
    ) -> DensificationBudgetPlan {
        let outputReserveTokens = densificationOutputReserveTokens(for: contextWindowTokens)
        let safetyMarginTokens = densificationSafetyMarginTokens(for: contextWindowTokens)
        let chunkPromptOverheadTokens = TokenCountEstimator.estimate(
            for: densificationChunkPrompt(
                inputText: "",
                appName: request.appName,
                windowTitle: request.windowTitle,
                chunkIndex: 1,
                totalChunks: 1,
                targetWordLimit: densificationPromptTargetWordLimitPlaceholder
            )
        )
        let availableChunkTokens = max(
            densificationMinimumChunkInputTokens,
            contextWindowTokens
                - densificationSystemInstructionTokenCount
                - chunkPromptOverheadTokens
                - outputReserveTokens
                - safetyMarginTokens
        )
        let dynamicChunkInputTokens = max(
            densificationMinimumChunkInputTokens,
            Int(Double(availableChunkTokens) * densificationInputUtilizationRatio(for: contextWindowTokens))
        )
        let chunkInputTokens = max(
            densificationMinimumChunkInputTokens,
            min(requestedChunkInputTokens, dynamicChunkInputTokens)
        )
        let mergePromptOverheadTokens = TokenCountEstimator.estimate(
            for: densificationMergePrompt(
                partials: [""],
                appName: request.appName,
                windowTitle: request.windowTitle,
                pass: 1,
                targetWordLimit: densificationPromptTargetWordLimitPlaceholder
            )
        )
        let availableMergeTokens = max(
            densificationMinimumChunkInputTokens,
            contextWindowTokens
                - densificationSystemInstructionTokenCount
                - mergePromptOverheadTokens
                - outputReserveTokens
                - safetyMarginTokens
        )
        let initialMergeInputTokens = max(
            densificationMinimumChunkInputTokens,
            min(chunkInputTokens, availableMergeTokens)
        )
        return DensificationBudgetPlan(
            contextWindowTokens: contextWindowTokens,
            chunkInputTokens: chunkInputTokens,
            initialMergeInputTokens: initialMergeInputTokens,
            chunkTargetWordLimit: densificationChunkTargetWordLimit(for: chunkInputTokens),
            mergeTargetWordLimit: densificationMergeTargetWordLimit(for: initialMergeInputTokens),
            outputReserveTokens: outputReserveTokens,
            safetyMarginTokens: safetyMarginTokens
        )
    }

    func densifyWithAdaptiveChunking(
        request: DensificationRequest,
        apiKey: String,
        model: String,
        contextWindowTokens: Int,
        stats: DensificationDebugStats
    ) async throws -> String {
        var chunkInputTokens = initialChunkInputBudget(
            request: request,
            contextWindowTokens: contextWindowTokens
        )
        while true {
            let budgetPlan = makeDensificationBudgetPlan(
                request: request,
                contextWindowTokens: contextWindowTokens,
                requestedChunkInputTokens: chunkInputTokens
            )
            do {
                return try await densifyInChunks(
                    request: request,
                    apiKey: apiKey,
                    model: model,
                    budgetPlan: budgetPlan,
                    stats: stats
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
                    "Densification exceeded context window. Retrying with smaller chunk budget [provider=\(provider.rawValue) contextWindowTokens=\(contextWindowTokens) previousChunkInputTokens=\(chunkInputTokens) nextChunkInputTokens=\(nextChunkInputTokens)]"
                )
                chunkInputTokens = nextChunkInputTokens
            }
        }
    }

    func densifyInChunks(
        request: DensificationRequest,
        apiKey: String,
        model: String,
        budgetPlan: DensificationBudgetPlan,
        stats: DensificationDebugStats
    ) async throws -> String {
        let planner = ContextWindowPlanner(
            maxChunkInputTokens: budgetPlan.chunkInputTokens,
            maxMergeInputTokens: budgetPlan.initialMergeInputTokens,
            minimumChunkInputTokens: densificationMinimumChunkInputTokens
        )
        let chunks = planner.chunkInput(request.inputText)
        guard !chunks.isEmpty else {
            return ""
        }
        let maxParallelRuns = max(
            1,
            min(providerWorkLimit(for: provider), chunks.count)
        )
        AppLogger.debug(
            "Densification chunk plan [provider=\(provider.rawValue) contextWindowTokens=\(budgetPlan.contextWindowTokens) chunkInputTokens=\(budgetPlan.chunkInputTokens) mergeInputTokens=\(budgetPlan.initialMergeInputTokens) outputReserveTokens=\(budgetPlan.outputReserveTokens) safetyMarginTokens=\(budgetPlan.safetyMarginTokens) chunkTargetWords=\(budgetPlan.chunkTargetWordLimit) mergeTargetWords=\(budgetPlan.mergeTargetWordLimit) inputEstimatedTokens=\(planner.estimatedTokenCount(for: request.inputText)) chunks=\(chunks.count) parallel=\(maxParallelRuns)]"
        )

        let chunkRuns = chunks.enumerated().map { index, chunk in
            let chunkPrompt = densificationChunkPrompt(
                inputText: chunk,
                appName: request.appName,
                windowTitle: request.windowTitle,
                chunkIndex: index + 1,
                totalChunks: chunks.count,
                targetWordLimit: budgetPlan.chunkTargetWordLimit
            )
            stats.runCount += 1
            return (
                index: index,
                run: stats.runCount,
                prompt: chunkPrompt
            )
        }
        let partials = try await withThrowingTaskGroup(of: (Int, String).self, returning: [String].self) { group in
            var nextChunkRunIndex = 0
            func enqueueNextChunkRun() {
                guard nextChunkRunIndex < chunkRuns.count else {
                    return
                }
                let chunkRun = chunkRuns[nextChunkRunIndex]
                nextChunkRunIndex += 1
                group.addTask {
                    let chunkStartedAt = Date()
                    let chunkOutput = try await requestText(
                        request: ProviderTextRequest(
                            systemInstruction: densificationSystemInstruction,
                            prompt: chunkRun.prompt
                        ),
                        apiKey: apiKey,
                        model: model
                    )
                    AppLogger.debug(
                        "Densification chunk run completed [provider=\(provider.rawValue) run=\(chunkRun.run) chunk=\(chunkRun.index + 1)/\(chunks.count) promptEstimatedTokens=\(planner.estimatedTokenCount(for: chunkRun.prompt)) outputEstimatedTokens=\(planner.estimatedTokenCount(for: chunkOutput)) seconds=\(formattedElapsedSeconds(since: chunkStartedAt))]"
                    )
                    return (chunkRun.index, chunkOutput)
                }
            }
            for _ in 0 ..< maxParallelRuns {
                enqueueNextChunkRun()
            }

            var outputs = Array(repeating: "", count: chunks.count)
            while let (index, chunkOutput) = try await group.next() {
                outputs[index] = chunkOutput
                enqueueNextChunkRun()
            }
            return outputs
        }
        return try await mergePartialsWithAdaptiveBudget(
            partials: partials,
            request: request,
            apiKey: apiKey,
            model: model,
            chunkInputTokens: budgetPlan.chunkInputTokens,
            initialMergeInputTokens: budgetPlan.initialMergeInputTokens,
            mergeTargetWordLimit: budgetPlan.mergeTargetWordLimit,
            stats: stats
        )
    }

    func mergePartialsWithAdaptiveBudget(
        partials: [String],
        request: DensificationRequest,
        apiKey: String,
        model: String,
        chunkInputTokens: Int,
        initialMergeInputTokens: Int,
        mergeTargetWordLimit: Int,
        stats: DensificationDebugStats
    ) async throws -> String {
        var mergeInputTokens = max(densificationMinimumChunkInputTokens, initialMergeInputTokens)
        while true {
            do {
                return try await mergePartials(
                    partials: partials,
                    request: request,
                    apiKey: apiKey,
                    model: model,
                    chunkInputTokens: chunkInputTokens,
                    mergeInputTokens: mergeInputTokens,
                    mergeTargetWordLimit: mergeTargetWordLimit,
                    stats: stats
                )
            } catch {
                guard isContextWindowExceededError(error), mergeInputTokens > densificationMinimumChunkInputTokens else {
                    throw error
                }
                let nextMergeInputTokens = max(densificationMinimumChunkInputTokens, mergeInputTokens / 2)
                guard nextMergeInputTokens < mergeInputTokens else {
                    throw error
                }
                AppLogger.debug(
                    "Densification merge exceeded context window. Retrying merge-only with smaller budget [provider=\(provider.rawValue) chunkInputTokens=\(chunkInputTokens) previousMergeInputTokens=\(mergeInputTokens) nextMergeInputTokens=\(nextMergeInputTokens)]"
                )
                mergeInputTokens = nextMergeInputTokens
            }
        }
    }

    func mergePartials(
        partials: [String],
        request: DensificationRequest,
        apiKey: String,
        model: String,
        chunkInputTokens: Int,
        mergeInputTokens: Int,
        mergeTargetWordLimit: Int,
        stats: DensificationDebugStats
    ) async throws -> String {
        let planner = ContextWindowPlanner(
            maxChunkInputTokens: chunkInputTokens,
            maxMergeInputTokens: mergeInputTokens,
            minimumChunkInputTokens: densificationMinimumChunkInputTokens
        )
        var mergedPartials = partials
        var pass = 1
        while mergedPartials.count > 1 {
            let mergeGroups = planner.mergeGroups(for: mergedPartials)
            let mergeParallelism = max(
                1,
                min(providerWorkLimit(for: provider), mergeGroups.count)
            )
            AppLogger.debug(
                "Densification merge pass planned [provider=\(provider.rawValue) pass=\(pass) mergeInputTokens=\(mergeInputTokens) inputPartials=\(mergedPartials.count) groups=\(mergeGroups.count) parallel=\(mergeParallelism)]"
            )
            if mergeGroups.count == mergedPartials.count, mergeGroups.allSatisfy({ $0.count == 1 }) {
                AppLogger.debug(
                    "Densification merge pass not reducing [provider=\(provider.rawValue) pass=\(pass) mergeInputTokens=\(mergeInputTokens) inputPartials=\(mergedPartials.count)]"
                )
                return mergedPartials.joined(separator: "\n\n")
            }

            let mergeRuns = mergeGroups.enumerated().map { groupIndex, mergeGroup in
                let mergePrompt = densificationMergePrompt(
                    partials: mergeGroup,
                    appName: request.appName,
                    windowTitle: request.windowTitle,
                    pass: pass,
                    targetWordLimit: mergeTargetWordLimit
                )
                stats.runCount += 1
                return (
                    groupIndex: groupIndex,
                    run: stats.runCount,
                    prompt: mergePrompt,
                    groupPartials: mergeGroup.count
                )
            }
            let reducedPartials = try await withThrowingTaskGroup(of: (Int, String).self, returning: [String].self) { group in
                var nextMergeRunIndex = 0
                func enqueueNextMergeRun() {
                    guard nextMergeRunIndex < mergeRuns.count else {
                        return
                    }
                    let mergeRun = mergeRuns[nextMergeRunIndex]
                    nextMergeRunIndex += 1
                    group.addTask {
                        let mergeStartedAt = Date()
                        let mergedOutput = try await requestText(
                            request: ProviderTextRequest(
                                systemInstruction: densificationSystemInstruction,
                                prompt: mergeRun.prompt
                            ),
                            apiKey: apiKey,
                            model: model
                        )
                        AppLogger.debug(
                            "Densification merge run completed [provider=\(provider.rawValue) run=\(mergeRun.run) pass=\(pass) mergeInputTokens=\(mergeInputTokens) group=\(mergeRun.groupIndex + 1)/\(mergeGroups.count) groupPartials=\(mergeRun.groupPartials) promptEstimatedTokens=\(planner.estimatedTokenCount(for: mergeRun.prompt)) outputEstimatedTokens=\(planner.estimatedTokenCount(for: mergedOutput)) seconds=\(formattedElapsedSeconds(since: mergeStartedAt))]"
                        )
                        return (mergeRun.groupIndex, mergedOutput)
                    }
                }
                for _ in 0 ..< mergeParallelism {
                    enqueueNextMergeRun()
                }

                var outputs = Array(repeating: "", count: mergeGroups.count)
                while let (groupIndex, mergedOutput) = try await group.next() {
                    outputs[groupIndex] = mergedOutput
                    enqueueNextMergeRun()
                }
                return outputs
            }
            AppLogger.debug(
                "Densification merge pass completed [provider=\(provider.rawValue) pass=\(pass) mergeInputTokens=\(mergeInputTokens) outputPartials=\(reducedPartials.count)]"
            )
            mergedPartials = reducedPartials
            pass += 1
        }

        return mergedPartials.first ?? ""
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
private let densificationMinimumChunkInputTokens = 320
private let smallContextWindowTokenLimit = 4_096
private let reactiveContextWindowTokenLimit = 100_000
private let densificationPromptTargetWordLimitPlaceholder = 260
private let densificationOutputReserveRatio = 0.24
private let densificationMinimumOutputReserveTokens = 280
private let densificationMaximumOutputReserveTokens = 2_400
private let densificationSafetyMarginRatio = 0.10
private let densificationMinimumSafetyMarginTokens = 120
private let densificationMaximumSafetyMarginTokens = 3_200
private let densificationSmallContextInputUtilizationRatio = 0.88
private let densificationLargeContextInputUtilizationRatio = 0.88
private let densificationChunkWordsPerInputToken = 0.16
private let densificationMergeWordsPerInputToken = 0.18
private let densificationMinimumChunkTargetWordLimit = 120
private let densificationMaximumChunkTargetWordLimit = 420
private let densificationMinimumMergeTargetWordLimit = 160
private let densificationMaximumMergeTargetWordLimit = 520
private let densificationSystemInstructionTokenCount = TokenCountEstimator.estimate(
    for: ProviderTextRequest(systemInstruction: densificationSystemInstruction, prompt: "").systemInstruction ?? ""
)
private func densificationOutputReserveTokens(for contextWindowTokens: Int) -> Int {
    let ratioBased = Int(Double(contextWindowTokens) * densificationOutputReserveRatio)
    return min(
        densificationMaximumOutputReserveTokens,
        max(densificationMinimumOutputReserveTokens, ratioBased)
    )
}

private func densificationSafetyMarginTokens(for contextWindowTokens: Int) -> Int {
    let ratioBased = Int(Double(contextWindowTokens) * densificationSafetyMarginRatio)
    return min(
        densificationMaximumSafetyMarginTokens,
        max(densificationMinimumSafetyMarginTokens, ratioBased)
    )
}

private func densificationInputUtilizationRatio(for contextWindowTokens: Int) -> Double {
    contextWindowTokens <= smallContextWindowTokenLimit
        ? densificationSmallContextInputUtilizationRatio
        : densificationLargeContextInputUtilizationRatio
}

private func densificationChunkTargetWordLimit(for chunkInputTokens: Int) -> Int {
    let dynamicLimit = Int(Double(chunkInputTokens) * densificationChunkWordsPerInputToken)
    return min(
        densificationMaximumChunkTargetWordLimit,
        max(densificationMinimumChunkTargetWordLimit, dynamicLimit)
    )
}

private func densificationMergeTargetWordLimit(for mergeInputTokens: Int) -> Int {
    let dynamicLimit = Int(Double(mergeInputTokens) * densificationMergeWordsPerInputToken)
    return min(
        densificationMaximumMergeTargetWordLimit,
        max(densificationMinimumMergeTargetWordLimit, dynamicLimit)
    )
}

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

private func densificationChunkPrompt(
    inputText: String,
    appName: String,
    windowTitle: String,
    chunkIndex: Int,
    totalChunks: Int,
    targetWordLimit: Int
) -> String {
    [
        "Extract essential context from this captured snapshot chunk.",
        "Chunk \(chunkIndex) of \(totalChunks).",
        "Max length: \(targetWordLimit) words.",
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
    pass: Int,
    targetWordLimit: Int
) -> String {
    [
        "Merge these partial summaries into one coherent snapshot context.",
        "Remove duplicates.",
        "Max length: \(targetWordLimit) words.",
        "App: \(appName)",
        "Window: \(windowTitle)",
        "",
        partials.enumerated().map { index, partial in
            "[\(index + 1)] \(partial)"
        }.joined(separator: "\n\n")
    ].joined(separator: "\n")
}
