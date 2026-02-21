import Foundation

public enum AppError: LocalizedError {
    case noFrontmostApp
    case captureTargetIsContextBrief
    case noCurrentContext
    case noCaptureToUndo
    case noCaptureToPromote
    case contextNotFound
    case snapshotNotFound
    case keyNotConfigured
    case providerNotConfigured
    case providerRequestTransientFailure(String)
    case providerRequestTimedOut(provider: ProviderName, timeoutSeconds: Int)
    case providerBinaryNotFound(provider: ProviderName, binary: String)
    case providerAuthenticationFailed(provider: ProviderName, details: String?)
    case providerModelUnavailable(provider: ProviderName, model: String, suggestions: [String])
    case providerRequestRejected(String)
    case densificationInputTooLong(estimatedTokens: Int, limit: Int)

    public var errorDescription: String? {
        switch self {
        case .noFrontmostApp:
            return "No frontmost app found."
        case .captureTargetIsContextBrief:
            return "Context Brief cannot capture its own UI. Switch to another app and try again."
        case .noCurrentContext:
            return "No current context selected."
        case .noCaptureToUndo:
            return "No snapshot to undo in current context."
        case .noCaptureToPromote:
            return "No snapshot to move into a new context."
        case .contextNotFound:
            return "Selected context was not found."
        case .snapshotNotFound:
            return "Selected snapshot was not found."
        case .keyNotConfigured:
            return "Required credentials are missing. Configure setup settings."
        case .providerNotConfigured:
            return "LLM CLI tool is not configured. Complete setup."
        case .providerRequestTransientFailure(let details):
            return details
        case .providerRequestTimedOut(let provider, let timeoutSeconds):
            return "\(provider.rawValue.capitalized) CLI request timed out after \(timeoutSeconds) seconds."
        case .providerBinaryNotFound(let provider, let binary):
            return "\(provider.rawValue.capitalized) CLI binary was not found (\(binary)). Install it or set the corresponding *_PATH environment variable."
        case .providerAuthenticationFailed(let provider, let details):
            if let details, !details.isEmpty {
                return "Authentication failed for \(provider.rawValue.capitalized) CLI: \(details)"
            }
            return "Authentication failed for \(provider.rawValue.capitalized) CLI. Re-authenticate and try again."
        case .providerModelUnavailable(let provider, let model, let suggestions):
            if suggestions.isEmpty {
                return "Model \(model) is not available for \(provider.rawValue.capitalized) CLI."
            }
            return "Model \(model) is not available for \(provider.rawValue.capitalized) CLI. Try: \(suggestions.joined(separator: ", "))"
        case .providerRequestRejected(let details):
            return details
        case .densificationInputTooLong(let estimated, let limit):
            return "Capture is too long to densify (about \(estimated) tokens; limit is \(limit)). Try a shorter selection or fewer pages."
        }
    }

    public var isRetryableProviderFailure: Bool {
        switch self {
        case .providerRequestTransientFailure, .providerRequestTimedOut:
            return true
        default:
            return false
        }
    }
}
