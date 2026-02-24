@testable import ContextGenerator
import XCTest

final class ProviderClientDensificationParsingTests: XCTestCase {
    func testParseDensificationEmbeddedPayloadParsesMarkdownWrappedJSONObject() {
        let raw = """
        ```json
        {
          "content": "Dense context",
          "title": "Short title"
        }
        ```
        """

        let payload = parseDensificationEmbeddedPayload(from: raw)

        XCTAssertEqual(payload?["content"] as? String, "Dense context")
        XCTAssertEqual(payload?["title"] as? String, "Short title")
    }

    func testParseDensificationEmbeddedPayloadReturnsNilForMalformedJSONObject() {
        let raw = """
        ```json
        {
          "content": "Dense context",
          "title": "Missing closing brace"
        ```
        """

        let payload = parseDensificationEmbeddedPayload(from: raw)

        XCTAssertNil(payload)
    }

    func testExtractOuterJSONObjectIgnoresBracesInsideStringValues() {
        let raw = """
        prefix
        {
          "content": "literal } and { inside text",
          "title": "ok"
        }
        suffix
        """

        let extracted = extractOuterJSONObject(from: raw)

        XCTAssertEqual(
            extracted?.trimmingCharacters(in: .whitespacesAndNewlines),
            """
            {
              "content": "literal } and { inside text",
              "title": "ok"
            }
            """
        )
    }

    func testParseDensificationResponseParsesWrappedInnerJSONFromResponseField() {
        let stdout = """
        {
          "response": "```json\\n{\\n  \\"content\\": \\"Dense context from inner payload\\",\\n  \\"title\\": \\"Inner title\\"\\n}\\n```",
          "session_id": "abc-123",
          "stats": {
            "models": {
              "gemini-2.5-flash": {
                "tokens": {
                  "total": 100
                }
              }
            }
          }
        }
        """

        let result = parseDensificationResponse(stdout: stdout)

        XCTAssertEqual(result.content, "Dense context from inner payload")
        XCTAssertEqual(result.title, "Inner title")
    }

    func testParseDensificationResponseFallsBackWhenInnerWrappedJSONIsMalformed() {
        let stdout = """
        {
          "response": "```json\\n{\\n  \\"content\\": \\"Dense context from inner payload\\",\\n  \\"title\\": \\"Inner title\\"\\n\\n```",
          "session_id": "abc-123"
        }
        """

        let result = parseDensificationResponse(stdout: stdout)

        XCTAssertTrue(result.content.hasPrefix("```json"))
        XCTAssertTrue(result.content.contains(#""content": "Dense context from inner payload""#))
        XCTAssertTrue(result.content.contains(#""title": "Inner title""#))
        XCTAssertNil(result.title)
    }
}
