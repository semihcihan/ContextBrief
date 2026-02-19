@testable import ContextGenerator
import XCTest

final class ContextWindowPlannerTests: XCTestCase {
    func testEstimatedTokenCountTreatsCJKAsDenserThanLatin() {
        let planner = ContextWindowPlanner()
        let latinText = String(repeating: "a", count: 300)
        let cjkText = String(repeating: "你", count: 300)

        XCTAssertLessThan(
            planner.estimatedTokenCount(for: latinText),
            planner.estimatedTokenCount(for: cjkText)
        )
    }

    func testChunkInputSplitsLargeTextIntoMultipleChunks() {
        let planner = ContextWindowPlanner()
        let longText = Array(repeating: String(repeating: "alpha beta gamma ", count: 120), count: 14)
            .joined(separator: "\n\n")

        let chunks = planner.chunkInput(longText)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { !($0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) })
        XCTAssertTrue(chunks.allSatisfy { planner.estimatedTokenCount(for: $0) <= 1800 })
    }

    func testMergeGroupsStayInsideMergeBudget() {
        let planner = ContextWindowPlanner()
        let partials = (1 ... 18).map { index in
            "Chunk \(index): " + String(repeating: "important context text ", count: 90)
        }

        let groups = planner.mergeGroups(for: partials)

        XCTAssertFalse(groups.isEmpty)
        XCTAssertTrue(groups.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(
            groups.allSatisfy { group in
                planner.estimatedTokenCount(for: group.joined(separator: "\n\n---\n\n")) <= 2000
            }
        )
    }
}
