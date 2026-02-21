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
    private static let logFileLock = NSLock()
    private static let logLineLimit = 4000

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        filePrint(level: "INFO", message: message)
        terminalPrint(level: "INFO", message: message)
    }

    public static func debug(_ message: String) {
        guard debugLoggingEnabled else {
            return
        }
        logger.debug("\(message, privacy: .public)")
        filePrint(level: "DEBUG", message: message)
        terminalPrint(level: "DEBUG", message: message)
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        filePrint(level: "ERROR", message: message)
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

    private static var logFileURL: URL? {
        if let path = ProcessInfo.processInfo.environment["CONTEXT_GENERATOR_LOG_FILE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let cwd = FileManager.default.currentDirectoryPath
        guard !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).appendingPathComponent(".logs.txt")
    }

    private static func filePrint(level: String, message: String) {
        guard let url = logFileURL else { return }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)\n"
        logFileLock.lock()
        defer { logFileLock.unlock() }
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try? data.append(to: url)
        } else {
            try? data.write(to: url)
        }
    }

    public static func filePrintMultiline(level: String, headline: String, body: String) {
        guard debugLoggingEnabled, let url = logFileURL else { return }
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        let truncated = body.count > logLineLimit
            ? String(body.prefix(logLineLimit)) + "\n... [truncated \(body.count - logLineLimit) chars]"
            : body
        let block = "[\(timestamp)] [\(level)] \(headline)\n\(truncated)\n"
        logFileLock.lock()
        defer { logFileLock.unlock() }
        guard let data = block.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try? data.append(to: url)
        } else {
            try? data.write(to: url)
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

private extension Data {
    func append(to url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try write(to: url)
            return
        }
        guard let handle = try? FileHandle(forUpdating: url) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(self)
    }
}
