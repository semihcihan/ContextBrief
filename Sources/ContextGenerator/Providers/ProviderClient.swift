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

private let providerRequestTimeoutSeconds: TimeInterval = 60
private let localDebugResponseDelayNanoseconds: UInt64 = 3_000_000_000
private let localDebugDensificationCharacterLimit = 200
private let densificationSystemInstruction = "You produce concise, complete context with no missing key information."
private let densificationMinimumChunkInputTokens = 320
private let appleContextWindowTokenLimit = 4_096
private let reactiveContextWindowTokenLimit = 100_000
private let densificationPromptTargetWordLimitPlaceholder = 260
private let densificationOutputReserveRatio = 0.24
private let densificationMinimumOutputReserveTokens = 280
private let densificationMaximumOutputReserveTokens = 2_400
private let densificationSafetyMarginRatio = 0.10
private let densificationMinimumSafetyMarginTokens = 120
private let densificationMaximumSafetyMarginTokens = 3_200
private let densificationSmallContextInputUtilizationRatio = 0.62
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
private let appleContextWindowExceededMessage = "Context Window Size Exceeded. Apple Foundation Models allow up to 4,096 tokens per session (including instructions, input, and output). Start a new session and retry with shorter input or output."

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
    contextWindowTokens <= appleContextWindowTokenLimit
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
        try await withProviderWorkPermit(provider: provider, operationName: "request_text") {
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
}

private struct AnthropicProviderClient: ProviderClient {
    let provider: ProviderName = .anthropic
    let session: URLSession

    func requestText(request: ProviderTextRequest, apiKey: String, model: String) async throws -> String {
        try await withProviderWorkPermit(provider: provider, operationName: "request_text") {
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
}

private struct GeminiProviderClient: ProviderClient {
    let provider: ProviderName = .gemini
    let session: URLSession

    func requestText(request: ProviderTextRequest, apiKey: String, model: String) async throws -> String {
        try await withProviderWorkPermit(provider: provider, operationName: "request_text") {
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
}

private struct AppleFoundationProviderClient: ProviderClient {
    let provider: ProviderName = .apple

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

#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            guard SystemLanguageModel.default.availability == .available else {
                throw AppError.providerRequestFailed(
                    "Apple Foundation Models are not available on this Mac."
                )
            }

            let stats = DensificationDebugStats()
            let output = try await densifyWithAdaptiveChunking(
                request: request,
                apiKey: apiKey,
                model: model,
                contextWindowTokens: appleContextWindowTokenLimit,
                stats: stats
            )
            AppLogger.debug(
                "Densification completed [provider=\(provider.rawValue) runs=\(stats.runCount) chunked=true seconds=\(formattedElapsedSeconds(since: startedAt))]"
            )
            return output
        }
#endif
        throw AppError.providerRequestFailed(
            "Apple Foundation Models are unavailable in this environment."
        )
    }

    func requestText(request: ProviderTextRequest, apiKey: String, model: String) async throws -> String {
        try await withProviderWorkPermit(provider: provider, operationName: "request_text") {
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
