import XCTest

@MainActor
final class KshiftIOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCreateTaskThroughSharedPlanner() throws {
        let app = launchPlanner()
        let addTask = firstMiaAddTask(in: app)
        addTask.tap()

        let titleField = taskTitleField(in: app)
        titleField.tap()
        titleField.typeText("UI evidence task")

        let save = app.buttons["保存"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(app.staticTexts["UI evidence task"].waitForExistence(timeout: 5))
    }

    func testCoreActionsMeetMinimumTouchTargets() throws {
        let app = launchPlanner()

        let actions = [
            element(in: app, identifier: "project-switcher", labelContains: "切换项目"),
            element(in: app, identifier: "add-task", labelContains: "添加任务"),
            element(in: app, identifier: "filter-button", labelContains: "筛选任务"),
            element(in: app, identifier: "refresh-button", labelContains: "刷新共享快照"),
            element(in: app, identifier: "sort-menu", labelContains: "排序"),
            element(in: app, identifier: "clear-selection", labelContains: "清除选择"),
        ]

        for action in actions {
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(action.frame.width, 44)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44)
        }

        let toggle = element(
            in: app,
            identifier: "toggle-task-task-launch-brief",
            labelContains: "标记为"
        )
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(toggle.frame.width, 44)
        XCTAssertGreaterThanOrEqual(toggle.frame.height, 44)
    }

    func testAccessibilityTextSizeKeepsCoreActionsAvailable() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        XCTAssertTrue(
            element(in: app, identifier: "project-switcher", labelContains: "切换项目")
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(
            element(in: app, identifier: "add-task", labelContains: "添加任务")
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(
            element(in: app, identifier: "filter-button", labelContains: "筛选任务")
                .waitForExistence(timeout: 8)
        )
    }

    func testSheetOpenAndClosePerformance() throws {
        let app = launchPlanner()
        let addTask = firstMiaAddTask(in: app)

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric()], options: options) {
            addTask.tap()
            let titleField = taskTitleField(in: app)
            XCTAssertTrue(titleField.waitForExistence(timeout: 5))

            let cancel = app.buttons["取消"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 3))
            cancel.tap()
            XCTAssertTrue(addTask.waitForExistence(timeout: 5))
        }
    }

    func testBoardScrollPerformance() throws {
        let app = launchPlanner()
        let board = element(in: app, identifier: "board-view", labelContains: "看板")
        XCTAssertTrue(board.waitForExistence(timeout: 5))

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric()], options: options) {
            board.swipeLeft()
            board.swipeRight()
        }
    }

    func testDragTaskPerformance() throws {
        let app = launchPlanner()
        let source = app.descendants(matching: .any)["task-task-launch-brief"].firstMatch
        let target = app.staticTexts["Noah Li"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(target.waitForExistence(timeout: 5))

        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [XCTClockMetric()], options: options) {
            source.press(forDuration: 0.2, thenDragTo: target)
        }
    }

    private func launchPlanner() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            element(in: app, identifier: "project-switcher", labelContains: "切换项目")
                .waitForExistence(timeout: 8)
        )
        return app
    }

    private func element(
        in app: XCUIApplication,
        identifier: String,
        labelContains: String
    ) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier == %@ OR label CONTAINS %@",
                    identifier,
                    labelContains
                )
            )
            .firstMatch
    }

    private func firstMiaAddTask(in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons.matching(
            NSPredicate(format: "label == %@", "为Mia Chen添加任务")
        ).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        return button
    }

    private func taskTitleField(in app: XCUIApplication) -> XCUIElement {
        let titleField = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ OR label == %@", "task-title", "任务标题"))
            .firstMatch
        if !titleField.waitForExistence(timeout: 5) {
            firstMiaAddTask(in: app).tap()
        }
        XCTAssertTrue(titleField.waitForExistence(timeout: 8))
        return titleField
    }
}
