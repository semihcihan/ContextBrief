import Foundation
import os

public enum AppLogger {
    private static let logger = Logger(subsystem: "ContextBrief", category: "Core")
    private static let debugEnvironmentKeys = [
        "CONTEXT_GENERATOR_DEBUG_LOGS",
        "CTX_DEBUG_LOGS"
    ]
    private static let terminalEnvironmentKeys = [
        "CONTEXT_GENERATOR_TERMINAL_LOGS",
        "CTX_TERMINAL_LOGS"
    ]

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        terminalPrint(level: "INFO", message: message)
    }

    public static func debug(_ message: String) {
        guard debugLoggingEnabled else {
            return
        }
        logger.debug("\(message, privacy: .public)")
        terminalPrint(level: "DEBUG", message: message)
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        terminalPrint(level: "ERROR", message: message)
    }

    public static var debugLoggingEnabled: Bool {
        if UserDefaults.standard.bool(forKey: "ContextBrief.DebugLogs") {
            return true
        }
        return debugEnvironmentKeys.contains { key in
            let value = ProcessInfo.processInfo.environment[key]?.lowercased() ?? ""
            return value == "1" || value == "true" || value == "yes" || value == "on"
        }
    }

    private static var terminalLoggingEnabled: Bool {
        terminalEnvironmentKeys.contains { key in
            let value = ProcessInfo.processInfo.environment[key]?.lowercased() ?? ""
            return value == "1" || value == "true" || value == "yes" || value == "on"
        }
    }

    private static func terminalPrint(level: String, message: String) {
        guard terminalLoggingEnabled else {
            return
        }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        print("[\(timestamp)] [\(level)] \(message)")
    }
}
