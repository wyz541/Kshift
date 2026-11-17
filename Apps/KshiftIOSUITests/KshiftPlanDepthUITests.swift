import XCTest

final class KshiftPlanDepthUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPlanDepthFlowAndAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launch()

        let board = app.buttons["看板"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 8))
        board.tap()

        let openPlanDepth = app.buttons["open-plan-depth"]
        XCTAssertTrue(openPlanDepth.waitForExistence(timeout: 8))
        openPlanDepth.tap()

        XCTAssertTrue(app.staticTexts["计划深度"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(identifier: "甘特").firstMatch.exists)

        app.buttons["甘特"].tap()
        XCTAssertTrue(app.staticTexts["跨日排期"].waitForExistence(timeout: 3))

        app.buttons["历史"].tap()
        XCTAssertTrue(app.staticTexts["审计与回退"].waitForExistence(timeout: 3))

        app.buttons["报告"].tap()
        XCTAssertTrue(app.staticTexts["尚未生成报告"].waitForExistence(timeout: 3))
        app.buttons["生成报告"].tap()
        XCTAssertTrue(app.staticTexts["来源 r7"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["close-plan-depth"].firstMatch.exists)

        var unexpectedIssues: [String] = []
        try app.performAccessibilityAudit(
            for: [
                .contrast,
                .dynamicType,
                .hitRegion,
                .textClipped,
                .sufficientElementDescription,
            ]
        ) { issue in
            let label = issue.element?.label ?? ""
            let identifier = issue.element?.identifier ?? ""
            let elementType = issue.element.map { String(describing: $0.elementType) } ?? ""
            let waivedNativeToolbarClose = identifier == "close-plan-depth"
                && (issue.auditType == .contrast || issue.auditType == .dynamicType)
            if !waivedNativeToolbarClose {
                unexpectedIssues.append(
                    "\(issue.compactDescription): \(issue.detailedDescription) [\(label)] id=\(identifier) type=\(elementType)"
                )
            }
            return true
        }
        XCTAssertTrue(unexpectedIssues.isEmpty, unexpectedIssues.joined(separator: "\n"))
    }
}
