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

public struct Snapshot: Codable, Identifiable, Hashable {
    public let id: UUID
    public let contextId: UUID
    public let createdAt: Date
    public let sequence: Int
    public var title: String
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
        title: String? = nil,
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
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.title = trimmedTitle.isEmpty ? "Snapshot \(sequence)" : trimmedTitle
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

    enum CodingKeys: String, CodingKey {
        case id
        case contextId
        case createdAt
        case sequence
        case title
        case sourceType
        case appName
        case bundleIdentifier
        case windowTitle
        case captureMethod
        case rawContent
        case ocrContent
        case denseContent
        case provider
        case model
        case accessibilityLineCount
        case ocrLineCount
        case processingDurationMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        contextId = try container.decode(UUID.self, forKey: .contextId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sequence = try container.decode(Int.self, forKey: .sequence)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Snapshot \(sequence)"
        sourceType = try container.decode(SourceType.self, forKey: .sourceType)
        appName = try container.decode(String.self, forKey: .appName)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        windowTitle = try container.decode(String.self, forKey: .windowTitle)
        captureMethod = try container.decode(CaptureMethod.self, forKey: .captureMethod)
        rawContent = try container.decode(String.self, forKey: .rawContent)
        ocrContent = try container.decode(String.self, forKey: .ocrContent)
        denseContent = try container.decode(String.self, forKey: .denseContent)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        accessibilityLineCount = try container.decodeIfPresent(Int.self, forKey: .accessibilityLineCount) ?? 0
        ocrLineCount = try container.decodeIfPresent(Int.self, forKey: .ocrLineCount) ?? 0
        processingDurationMs = try container.decodeIfPresent(Int.self, forKey: .processingDurationMs) ?? 0
    }

    public static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
