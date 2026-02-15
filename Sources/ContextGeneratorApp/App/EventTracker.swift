import FirebaseAnalytics
import Foundation

enum AppEvent: String {
    case appLaunch = "app_launch"
    case appReady = "app_ready"
    case menuOpened = "menu_opened"
    case windowSectionOpened = "window_section_opened"
    case settingsOpened = "settings_opened"
    case contextLibraryOpened = "context_library_opened"
    case captureRequested = "capture_requested"
    case captureBlocked = "capture_blocked"
    case captureStarted = "capture_started"
    case captureSucceeded = "capture_succeeded"
    case captureFailed = "capture_failed"
    case hotkeyTriggered = "hotkey_triggered"
    case undoRequested = "undo_requested"
    case undoSucceeded = "undo_succeeded"
    case undoFailed = "undo_failed"
    case promoteRequested = "promote_requested"
    case promoteSucceeded = "promote_succeeded"
    case promoteFailed = "promote_failed"
    case newContextRequested = "new_context_requested"
    case newContextSucceeded = "new_context_succeeded"
    case newContextFailed = "new_context_failed"
    case copyContextRequested = "copy_context_requested"
    case copyContextSucceeded = "copy_context_succeeded"
    case copyContextFailed = "copy_context_failed"
    case shortcutRegistrationFailed = "shortcut_registration_failed"
}

final class EventTracker {
    static let shared = EventTracker()

    private init() {}

    func track(_ event: AppEvent, parameters: [String: Any] = [:]) {
        Analytics.logEvent(event.rawValue, parameters: sanitizedParameters(parameters))
    }

    private func sanitizedParameters(_ parameters: [String: Any]) -> [String: Any]? {
        guard !parameters.isEmpty else {
            return nil
        }
        var sanitized: [String: Any] = [:]
        for (key, value) in parameters {
            if let string = value as? String {
                sanitized[key] = string
                continue
            }
            if let int = value as? Int {
                sanitized[key] = NSNumber(value: int)
                continue
            }
            if let bool = value as? Bool {
                sanitized[key] = NSNumber(value: bool)
                continue
            }
            if let double = value as? Double {
                sanitized[key] = NSNumber(value: double)
                continue
            }
            if let float = value as? Float {
                sanitized[key] = NSNumber(value: float)
            }
        }
        return sanitized.isEmpty ? nil : sanitized
    }
}
