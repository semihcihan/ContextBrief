import Foundation
import os

public enum AppLogger {
    private static let logger = Logger(subsystem: "ContextGenerator", category: "Core")

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
