import XCTest
@testable import KshiftUI

final class MarkdownEditorTests: XCTestCase {
    func testMarkdownBlockParserPreservesDocumentStructure() {
        let blocks = MarkdownBlockParser.parse(
            """
            # Heading

            Paragraph with **bold** text.

            - First
            1. Second

            > Quote

            ---

            ```swift
            let value = 1
            ```
            """
        )

        XCTAssertEqual(blocks[0], .heading(level: 1, text: "Heading"))
        XCTAssertEqual(blocks[1], .paragraph("Paragraph with **bold** text."))
        XCTAssertEqual(blocks[2], .bullet("First"))
        XCTAssertEqual(blocks[3], .numbered("1", "Second"))
        XCTAssertEqual(blocks[4], .quote("Quote"))
        XCTAssertEqual(blocks[5], .divider)
        XCTAssertEqual(blocks[6], .code("let value = 1"))
    }
}
