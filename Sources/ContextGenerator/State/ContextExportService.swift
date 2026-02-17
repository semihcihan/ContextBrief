import Foundation

public enum ExportMode {
    case dense
}

public final class ContextExportService {
    private let repository: ContextRepositorying

    public init(repository: ContextRepositorying) {
        self.repository = repository
    }

    public func exportText(contextId: UUID, mode: ExportMode) throws -> String {
        let context = try repository.context(id: contextId)
        guard let context else {
            throw AppError.contextNotFound
        }

        let snapshots = try repository.snapshots(in: context.id).filter { $0.status == .ready }
        let body = snapshots.enumerated().map { index, snapshot in
            "[\(index + 1)] \(snapshot.denseContent)"
        }.joined(separator: "\n\n")

        return [
            "Context: \(context.title)",
            "Snapshots: \(snapshots.count)",
            "",
            body
        ].joined(separator: "\n")
    }
}
