import Foundation

public enum ExportMode {
    case dense
    case raw
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

        let snapshots = try repository.snapshots(in: context.id)
        let body = snapshots.enumerated().map { index, snapshot in
            switch mode {
            case .dense:
                return "[\(index + 1)] \(snapshot.denseContent)"
            case .raw:
                return "[\(index + 1)] \(snapshot.rawContent)"
            }
        }.joined(separator: "\n\n")

        return [
            "Context: \(context.title)",
            "Snapshots: \(snapshots.count)",
            "",
            body
        ].joined(separator: "\n")
    }
}
