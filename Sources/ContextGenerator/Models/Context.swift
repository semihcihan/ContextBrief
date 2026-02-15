import Foundation

public struct Context: Codable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date
    public var snapshotCount: Int

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        snapshotCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.snapshotCount = snapshotCount
    }

}
