import Foundation

public enum AppError: LocalizedError {
    case noFrontmostApp
    case noCurrentContext
    case noCaptureToUndo
    case noCaptureToPromote
    case contextNotFound
    case keyNotConfigured
    case providerNotConfigured

    public var errorDescription: String? {
        switch self {
        case .noFrontmostApp:
            return "No frontmost app found."
        case .noCurrentContext:
            return "No current context selected."
        case .noCaptureToUndo:
            return "No capture piece to undo in current context."
        case .noCaptureToPromote:
            return "No capture piece to move into a new context."
        case .contextNotFound:
            return "Selected context was not found."
        case .keyNotConfigured:
            return "API key is missing. Configure it in Settings."
        case .providerNotConfigured:
            return "Provider is not configured. Complete onboarding."
        }
    }
}
