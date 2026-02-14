import ContextGenerator
import XCTest

final class ContextRepositoryTests: XCTestCase {
    func testRepositoryPersistsContextAndSnapshots() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = ContextRepository(rootURL: tempRoot)

        let context = try repo.createContext(title: "Repo Test")
        let snapshot = Snapshot(
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
        try repo.appendSnapshot(snapshot)

        let contexts = try repo.listContexts()
        XCTAssertEqual(contexts.first?.snapshotCount, 1)

        let snapshots = try repo.snapshots(in: context.id)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.denseContent, "dense")
    }
}
