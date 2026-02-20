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

public enum SnapshotStatus: String, Codable {
    case ready
    case failed
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
    public let filteredCombinedText: String?
    public let ocrContent: String
    public let denseContent: String
    public let provider: String?
    public let model: String?
    public let accessibilityLineCount: Int
    public let ocrLineCount: Int
    public let processingDurationMs: Int
    public var status: SnapshotStatus
    public var failureMessage: String?
    public var retryCount: Int
    public var lastAttemptAt: Date?

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
        filteredCombinedText: String? = nil,
        ocrContent: String,
        denseContent: String,
        provider: String? = nil,
        model: String? = nil,
        accessibilityLineCount: Int = 0,
        ocrLineCount: Int = 0,
        processingDurationMs: Int = 0,
        status: SnapshotStatus = .ready,
        failureMessage: String? = nil,
        retryCount: Int = 0,
        lastAttemptAt: Date? = nil
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
        self.filteredCombinedText = filteredCombinedText
        self.ocrContent = ocrContent
        self.denseContent = denseContent
        self.provider = provider
        self.model = model
        self.accessibilityLineCount = accessibilityLineCount
        self.ocrLineCount = ocrLineCount
        self.processingDurationMs = processingDurationMs
        self.status = status
        self.failureMessage = failureMessage
        self.retryCount = retryCount
        self.lastAttemptAt = lastAttemptAt
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
        case filteredCombinedText
        case ocrContent
        case denseContent
        case provider
        case model
        case accessibilityLineCount
        case ocrLineCount
        case processingDurationMs
        case status
        case failureMessage
        case retryCount
        case lastAttemptAt
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
        filteredCombinedText = try container.decodeIfPresent(String.self, forKey: .filteredCombinedText)
        ocrContent = try container.decode(String.self, forKey: .ocrContent)
        denseContent = try container.decode(String.self, forKey: .denseContent)
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        accessibilityLineCount = try container.decodeIfPresent(Int.self, forKey: .accessibilityLineCount) ?? 0
        ocrLineCount = try container.decodeIfPresent(Int.self, forKey: .ocrLineCount) ?? 0
        processingDurationMs = try container.decodeIfPresent(Int.self, forKey: .processingDurationMs) ?? 0
        status = try container.decodeIfPresent(SnapshotStatus.self, forKey: .status) ?? .ready
        failureMessage = try container.decodeIfPresent(String.self, forKey: .failureMessage)
        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
        lastAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
    }

    public static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
