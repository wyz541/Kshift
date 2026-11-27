import XCTest

final class KshiftPlanDepthUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPlanDepthFlowAndAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KSHIFT_DEMO_MODE"] = "1"
        app.launchEnvironment["KSHIFT_USE_FFI"] = "0"
        app.launchEnvironment["KSHIFT_RESET_PLANNER_VIEW_STATE"] = "1"
        app.launch()

        let board = app.buttons["看板"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 8))
        board.tap()

        let openPlanDepth = app.buttons["open-plan-depth"]
        XCTAssertTrue(openPlanDepth.waitForExistence(timeout: 8))
        openPlanDepth.tap()

        XCTAssertTrue(app.staticTexts["计划深度"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.buttons.matching(identifier: "甘特").firstMatch.exists)

        app.buttons["甘特"].tap()
        XCTAssertTrue(app.staticTexts["跨日排期"].waitForExistence(timeout: 3))
        let ganttScroll = app.scrollViews["plan-depth-gantt-scroll"].firstMatch
        if ganttScroll.exists {
            ganttScroll.swipeLeft()
        }
        let delayedRow = app.descendants(matching: .any)[
            "plan-depth-gantt-task-e0000000-0000-4000-8000-000000000003"
        ].firstMatch
        XCTAssertTrue(delayedRow.waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertTrue(
            delayedRow.label.contains("延期 2 天") || delayedRow.value as? String == "延期 2 天",
            delayedRow.debugDescription
        )
        attachScreenshot(app, name: "ios-gantt-delay")

        delayedRow.tap()
        XCTAssertTrue(app.staticTexts["任务详情"].waitForExistence(timeout: 3))
        attachScreenshot(app, name: "ios-delay-task-detail")
        let rescheduleButton = app.buttons[
            "plan-depth-reschedule-e0000000-0000-4000-8000-000000000003"
        ].firstMatch
        XCTAssertTrue(rescheduleButton.waitForExistence(timeout: 3), app.debugDescription)
        rescheduleButton.tap()
        XCTAssertTrue(app.staticTexts["修改排期"].waitForExistence(timeout: 3))
        app.swipeUp()
        attachScreenshot(app, name: "ios-reschedule-editor")
        app.buttons["取消"].firstMatch.tap()
        app.buttons["关闭"].firstMatch.tap()

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

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
