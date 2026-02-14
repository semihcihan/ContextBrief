import Foundation

public struct TrashedContext: Codable, Identifiable, Equatable {
    public let id: UUID
    public let context: Context
    public let snapshots: [Snapshot]
    public let deletedAt: Date

    public init(
        id: UUID = UUID(),
        context: Context,
        snapshots: [Snapshot],
        deletedAt: Date = Date()
    ) {
        self.id = id
        self.context = context
        self.snapshots = snapshots
        self.deletedAt = deletedAt
    }
}
