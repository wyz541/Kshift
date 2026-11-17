import XCTest
@testable import KshiftUI

final class TaskTagTests: XCTestCase {
    func testTagInputSplitsAndTrimsValues() {
        XCTAssertEqual(
            TaskTagValues.normalized(" launch, 审核，review\n final "),
            ["launch", "审核", "review", "final"]
        )
    }

    func testAddingTagsRemovesEmptyValuesAndCaseInsensitiveDuplicates() {
        XCTAssertEqual(
            TaskTagValues.adding("Launch, review, , REVIEW, launch", to: ["launch"]),
            ["launch", "review"]
        )
    }
}
