import Foundation

public enum AppError: LocalizedError {
    case noFrontmostApp
    case noCurrentContext
    case noCaptureToUndo
    case noCaptureToPromote
    case contextNotFound
    case snapshotNotFound
    case keyNotConfigured
    case providerNotConfigured
    case providerRequestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noFrontmostApp:
            return "No frontmost app found."
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
            return "API key is missing. Configure it in Settings."
        case .providerNotConfigured:
            return "Provider is not configured. Complete onboarding."
        case .providerRequestFailed(let details):
            return details
        }
    }
}
