import Foundation

public enum SourceType: String, Codable {
    case desktopApp = "desktop_app"
    case browserTab = "browser_tab"
}

public enum CaptureMethod: String, Codable {
    case accessibility
    case screenshotOCR = "screenshot_ocr"
    case hybrid
    case none
}

public struct CapturePiece: Codable, Identifiable, Equatable {
    public let id: UUID
    public let contextId: UUID
    public let createdAt: Date
    public let sequence: Int
    public let sourceType: SourceType
    public let appName: String
    public let bundleIdentifier: String
    public let windowTitle: String
    public let captureMethod: CaptureMethod
    public let rawContent: String
    public let ocrContent: String
    public let denseContent: String
    public let provider: String?
    public let model: String?
    public let accessibilityLineCount: Int
    public let ocrLineCount: Int
    public let processingDurationMs: Int

    public init(
        id: UUID = UUID(),
        contextId: UUID,
        createdAt: Date = Date(),
        sequence: Int,
        sourceType: SourceType,
        appName: String,
        bundleIdentifier: String,
        windowTitle: String,
        captureMethod: CaptureMethod,
        rawContent: String,
        ocrContent: String,
        denseContent: String,
        provider: String? = nil,
        model: String? = nil,
        accessibilityLineCount: Int = 0,
        ocrLineCount: Int = 0,
        processingDurationMs: Int = 0
    ) {
        self.id = id
        self.contextId = contextId
        self.createdAt = createdAt
        self.sequence = sequence
        self.sourceType = sourceType
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.captureMethod = captureMethod
        self.rawContent = rawContent
        self.ocrContent = ocrContent
        self.denseContent = denseContent
        self.provider = provider
        self.model = model
        self.accessibilityLineCount = accessibilityLineCount
        self.ocrLineCount = ocrLineCount
        self.processingDurationMs = processingDurationMs
    }
}
