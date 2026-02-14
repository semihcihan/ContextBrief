import Foundation

public struct TrashedSnapshot: Codable, Identifiable, Equatable {
    public let id: UUID
    public let snapshot: Snapshot
    public let deletedAt: Date
    public let sourceContextTitle: String

    public init(
        id: UUID = UUID(),
        snapshot: Snapshot,
        deletedAt: Date = Date(),
        sourceContextTitle: String
    ) {
        self.id = id
        self.snapshot = snapshot
        self.deletedAt = deletedAt
        self.sourceContextTitle = sourceContextTitle
    }
}
