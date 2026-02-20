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
    case providerRequestFailed(String)
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
        case .providerRequestFailed(let details):
            return details
        case .densificationInputTooLong(let estimated, let limit):
            return "Capture is too long to densify (about \(estimated) tokens; limit is \(limit)). Try a shorter selection or fewer pages."
        }
    }
}
