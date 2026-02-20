import Foundation

public struct CapturedSnapshot: Codable, Equatable {
    public let id: UUID
    public let capturedAt: Date
    public let sourceType: SourceType
    public let appName: String
    public let bundleIdentifier: String
    public let windowTitle: String
    public let captureMethod: CaptureMethod
    public let accessibilityText: String
    public let ocrText: String
    public let combinedText: String
    public let filteredCombinedText: String?
    public let diagnostics: CaptureDiagnostics

    public init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        sourceType: SourceType,
        appName: String,
        bundleIdentifier: String,
        windowTitle: String,
        captureMethod: CaptureMethod,
        accessibilityText: String,
        ocrText: String,
        combinedText: String,
        filteredCombinedText: String? = nil,
        diagnostics: CaptureDiagnostics
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.sourceType = sourceType
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.captureMethod = captureMethod
        self.accessibilityText = accessibilityText
        self.ocrText = ocrText
        self.combinedText = combinedText
        self.filteredCombinedText = filteredCombinedText
        self.diagnostics = diagnostics
    }
}

public struct CaptureDiagnostics: Codable, Equatable {
    public let accessibilityLineCount: Int
    public let ocrLineCount: Int
    public let processingDurationMs: Int
    public let usedFallbackOCR: Bool

    public init(
        accessibilityLineCount: Int,
        ocrLineCount: Int,
        processingDurationMs: Int,
        usedFallbackOCR: Bool
    ) {
        self.accessibilityLineCount = accessibilityLineCount
        self.ocrLineCount = ocrLineCount
        self.processingDurationMs = processingDurationMs
        self.usedFallbackOCR = usedFallbackOCR
    }
}
