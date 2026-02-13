import ContextGenerator
import XCTest

final class ContextRepositoryTests: XCTestCase {
    func testRepositoryPersistsContextAndPieces() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)

        let context = try repo.createContext(title: "Repo Test")
        let piece = CapturePiece(
            contextId: context.id,
            sequence: 1,
            sourceType: .desktopApp,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            windowTitle: "Editor",
            captureMethod: .accessibility,
            rawContent: "raw",
            ocrContent: "",
            denseContent: "dense"
        )
        try repo.appendPiece(piece)

        let contexts = try repo.listContexts()
        XCTAssertEqual(contexts.first?.pieceCount, 1)

        let pieces = try repo.pieces(in: context.id)
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces.first?.denseContent, "dense")
    }
}
