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

        let pieces = try repository.pieces(in: context.id)
        let body = pieces.enumerated().map { index, piece in
            switch mode {
            case .dense:
                return "[\(index + 1)] \(piece.denseContent)"
            case .raw:
                return "[\(index + 1)] \(piece.rawContent)"
            }
        }.joined(separator: "\n\n")

        return [
            "Context: \(context.title)",
            "Pieces: \(pieces.count)",
            "",
            body
        ].joined(separator: "\n")
    }
}
