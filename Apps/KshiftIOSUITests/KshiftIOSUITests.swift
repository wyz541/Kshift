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

        let created = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "UI evidence task"))
            .firstMatch
        if !created.waitForExistence(timeout: 3) {
            let column = app.scrollViews["board-column-person-mia"].firstMatch
            if column.waitForExistence(timeout: 3) {
                for _ in 0..<3 where !created.exists {
                    column.swipeUp()
                }
            }
        }
        XCTAssertTrue(created.waitForExistence(timeout: 5), app.debugDescription)
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

    func testAccessibilityAudit() throws {
        let app = launchPlanner()
        let waivedDynamicTypeLabels = Set(["Launch Room", "Ship brief"])
        var unexpectedIssues: [String] = []

        try app.performAccessibilityAudit { issue in
            let label = issue.element?.label ?? ""
            let waived = issue.auditType == .dynamicType
                && waivedDynamicTypeLabels.contains(label)
            if !waived {
                unexpectedIssues.append(
                    "\(issue.compactDescription): \(issue.detailedDescription) [\(label)]"
                )
            }
            // Return true so this test reports one deterministic assertion below.
            return true
        }

        XCTAssertTrue(unexpectedIssues.isEmpty, unexpectedIssues.joined(separator: "\n"))
    }

    func testAccessibilityTextSizeKeepsCoreActionsAvailable() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launchEnvironment["KSHIFT_DEMO_MODE"] = "1"
        app.launch()

        let projectSwitcher = element(
            in: app,
            identifier: "project-switcher",
            labelContains: "切换项目"
        )
        let selectedDate = app.descendants(matching: .any)["selected-date"].firstMatch
        XCTAssertTrue(projectSwitcher.waitForExistence(timeout: 8))
        XCTAssertTrue(selectedDate.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(projectSwitcher.frame.maxY, selectedDate.frame.minY)
        XCTAssertTrue(
            element(in: app, identifier: "add-task", labelContains: "添加任务")
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(
            element(in: app, identifier: "filter-button", labelContains: "筛选任务")
                .waitForExistence(timeout: 8)
        )
    }

    func testBothProjectTimeZonesAndLiveUIWriteE2E() throws {
        let app = try launchLivePlanner()
        attachScreenshot(app, named: "ios-live-server")
        let selectedDate = app.descendants(matching: .any)["selected-date"].firstMatch
        XCTAssertTrue(selectedDate.waitForExistence(timeout: 8))
        XCTAssertTrue(selectedDate.label.contains("November 15"), selectedDate.label)
        XCTAssertTrue(app.staticTexts["当日任务 3"].waitForExistence(timeout: 8))

        app.buttons["前一天"].firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "selected-date", "November 14"))
                .firstMatch
                .waitForExistence(timeout: 8)
        )
        app.buttons["今天"].firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "selected-date", "November 15"))
                .firstMatch
                .waitForExistence(timeout: 8)
        )

        app.buttons["日历"].firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["calendar-view"]
                .waitForExistence(timeout: 8),
            app.debugDescription
        )
        let projectToday = app.descendants(matching: .any)["calendar-day-2026-11-15"].firstMatch
        XCTAssertTrue(projectToday.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(projectToday.label.contains("3 项任务"), projectToday.label)
        XCTAssertTrue(projectToday.label.contains("今天"), projectToday.label)
        app.buttons["看板"].firstMatch.tap()

        let initialTask = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "Shared roadmap task"))
            .firstMatch
        XCTAssertTrue(initialTask.waitForExistence(timeout: 15), app.debugDescription)
        initialTask.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["task-detail"]
                .waitForExistence(timeout: 8),
            app.debugDescription
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "创建任务 Shared roadmap task"))
                .firstMatch
                .waitForExistence(timeout: 8),
            app.debugDescription
        )
        app.buttons["关闭"].firstMatch.tap()

        firstMiaAddTask(in: app).tap()
        let titleField = taskTitleField(in: app)
        titleField.tap()
        titleField.typeText("Live UI created task")
        app.buttons["保存"].firstMatch.tap()

        XCTAssertTrue(
            app.staticTexts["当日任务 4"].waitForExistence(timeout: 15),
            app.debugDescription
        )

        let projectSwitcher = element(
            in: app,
            identifier: "project-switcher",
            labelContains: "切换项目"
        )
        XCTAssertTrue(projectSwitcher.waitForExistence(timeout: 8))
        projectSwitcher.tap()
        let beta = app.buttons["Beta Project"].firstMatch
        XCTAssertTrue(beta.waitForExistence(timeout: 8), app.debugDescription)
        beta.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "selected-date", "November 14"))
                .firstMatch
                .waitForExistence(timeout: 15),
            app.debugDescription
        )
        XCTAssertTrue(app.staticTexts["当日任务 1"].waitForExistence(timeout: 8))
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
        app.launchEnvironment["KSHIFT_DEMO_MODE"] = "1"
        app.launch()
        XCTAssertTrue(
            element(in: app, identifier: "project-switcher", labelContains: "切换项目")
                .waitForExistence(timeout: 8)
        )
        return app
    }

    private func launchLivePlanner() throws -> XCUIApplication {
        let environment = ProcessInfo.processInfo.environment
        guard let endpoint = environment["KSHIFT_ENDPOINT"],
              let token = environment["KSHIFT_TOKEN"],
              let actorID = environment["KSHIFT_ACTOR_ID"],
              let primaryProject = environment["KSHIFT_E2E_PRIMARY_PROJECT"],
              let userTimeZone = environment["KSHIFT_USER_TIME_ZONE"],
              let now = environment["KSHIFT_NOW"]
        else {
            throw XCTSkip("Set live UI server environment to run the live E2E test.")
        }
        let caPEM: String
        if let value = environment["KSHIFT_CA_PEM"] {
            caPEM = value
        } else if let caPath = environment["KSHIFT_CA_PATH"] {
            caPEM = try String(contentsOfFile: caPath, encoding: .utf8)
        } else {
            throw XCTSkip("Set KSHIFT_CA_PEM or KSHIFT_CA_PATH.")
        }
        let app = XCUIApplication()
        app.launchEnvironment["KSHIFT_USE_FFI"] = "1"
        app.launchEnvironment["KSHIFT_ENDPOINT"] = endpoint
        app.launchEnvironment["KSHIFT_CA_PEM"] = caPEM
        app.launchEnvironment["KSHIFT_TOKEN"] = token
        app.launchEnvironment["KSHIFT_ACTOR_ID"] = actorID
        app.launchEnvironment["KSHIFT_TLS_DOMAIN"] = "localhost"
        app.launchEnvironment["KSHIFT_USER_TIME_ZONE"] = userTimeZone
        app.launchEnvironment["KSHIFT_NOW"] = now
        app.launch()
        XCTAssertTrue(
            element(in: app, identifier: "project-switcher", labelContains: primaryProject)
                .waitForExistence(timeout: 15),
            app.debugDescription
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

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
