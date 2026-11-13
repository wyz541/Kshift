import XCTest

final class KshiftPlanDepthUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPlanDepthFlowAndAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launch()

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

        try app.performAccessibilityAudit(
            for: [
                .contrast,
                .dynamicType,
                .hitRegion,
                .textClipped,
                .sufficientElementDescription,
            ]
        )
    }
}
