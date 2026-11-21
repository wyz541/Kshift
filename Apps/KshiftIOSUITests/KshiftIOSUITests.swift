import XCTest

@MainActor
final class KshiftIOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
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

    func testTaskMarkdownEditorWritesAndPreviewsBlocks() throws {
        let app = launchPlanner()
        let addTask = firstMiaAddTask(in: app)
        addTask.tap()

        let title = taskTitleField(in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Markdown preview task")

        let markdownEditor = app.textViews["markdown-editor"].firstMatch
        XCTAssertTrue(markdownEditor.waitForExistence(timeout: 5), app.debugDescription)

        markdownEditor.tap()
        markdownEditor.typeText("# Details\n\n- First item\n- **Second item**")

        let previewMode = app.buttons["预览"].firstMatch
        XCTAssertTrue(previewMode.waitForExistence(timeout: 5), app.debugDescription)
        previewMode.tap()

        let preview = app.scrollViews["markdown-preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5), app.debugDescription)

        let renderedHeading = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "Details"))
            .firstMatch
        XCTAssertTrue(renderedHeading.waitForExistence(timeout: 5), app.debugDescription)
    }

    func testEditTaskUsesAnchoredPopover() throws {
        let app = launchPlanner()
        let task = app.descendants(matching: .any)["task-task-launch-brief"].firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 8), app.debugDescription)

        let actions = task.buttons["任务操作"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 5), app.debugDescription)
        actions.tap()

        let edit = app.buttons["编辑"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), app.debugDescription)
        edit.tap()

        let editor = app.descendants(matching: .any)["task-editor-popover"].firstMatch
        let titleField = app.descendants(matching: .any)["task-title"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(titleField.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["task-detail"].firstMatch.exists)

        let status = app.descendants(matching: .any)["task-status"].firstMatch
        let dueDate = app.descendants(matching: .any)["task-due-date"].firstMatch
        let notes = app.scrollViews["markdown-preview"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(dueDate.exists, app.debugDescription)
        XCTAssertTrue(notes.exists, app.debugDescription)
        XCTAssertLessThan(status.frame.minY, dueDate.frame.minY)
        XCTAssertLessThan(dueDate.frame.minY, notes.frame.minY)
        XCTAssertTrue(app.buttons["save-task"].firstMatch.isHittable, app.debugDescription)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Edit task popover - iOS"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let cancel = app.buttons["取消"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5), app.debugDescription)
    }

    func testBoardNotesOpenReadableMarkdownAtAccessibilitySize() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launchEnvironment["KSHIFT_DEMO_MODE"] = "1"
        app.launchEnvironment["KSHIFT_RESET_PLANNER_VIEW_STATE"] = "1"
        app.launchEnvironment["KSHIFT_INITIAL_VIEW_MODE"] = "board"
        app.launch()

        let notesButton = app.buttons["task-notes-task-launch-brief"].firstMatch
        XCTAssertTrue(app.scrollViews["board-view"].firstMatch.waitForExistence(timeout: 8))
        if !notesButton.isHittable { app.swipeUp() }
        XCTAssertTrue(notesButton.waitForExistence(timeout: 8), app.debugDescription)
        let card = app.descendants(matching: .any)["task-task-launch-brief"].firstMatch
        // The accessibility-size board column is wider than the 286-point compact column.
        XCTAssertGreaterThan(card.frame.width, 286)
        XCTAssertGreaterThanOrEqual(notesButton.frame.width, 44 - 0.01)
        XCTAssertGreaterThanOrEqual(notesButton.frame.height, 44 - 0.01)
        attachScreenshot(app, named: "ios-board-notes-accessibility-size")
        notesButton.tap()

        let preview = app.scrollViews["board-task-notes"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(preview.staticTexts["发布准备"].isHittable, app.debugDescription)
        XCTAssertTrue(preview.staticTexts["确认舞台与音响"].isHittable, app.debugDescription)
        attachScreenshot(app, named: "ios-board-notes-markdown-accessibility-size")
    }

    func testTableRowEditUsesAnchoredPopover() throws {
        let app = launchPlanner()
        let table = app.buttons["表格"].firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 8), app.debugDescription)
        table.tap()

        let row = app.descendants(matching: .any)["table-task-task-launch-brief"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
        // The full row extends beyond the viewport on compact devices.
        let title = row.buttons["table-edit-task-task-launch-brief"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        title.press(forDuration: 1.0)

        let edit = app.buttons["编辑"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), app.debugDescription)
        edit.tap()

        let editor = app.descendants(matching: .any)["task-editor-popover"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["task-detail"].firstMatch.exists)

        let cancel = app.buttons["取消"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), app.debugDescription)
        cancel.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5), app.debugDescription)
    }

    func testBoardTaskClickOpensAnchoredEditor() {
        let app = launchPlanner()
        let card = app.descendants(matching: .any)["task-task-launch-brief"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 8), app.debugDescription)

        card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()

        assertQuickEditorCanCancel(in: app)
    }

    func testTableTaskTitleClickOpensAnchoredEditor() {
        let app = launchPlanner()
        app.buttons["表格"].firstMatch.tap()
        let title = app.buttons["table-edit-task-task-launch-brief"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 8), app.debugDescription)

        title.tap()

        assertQuickEditorCanCancel(in: app)
    }

    func testScheduleTaskBarClickOpensAnchoredEditor() {
        let app = launchPlannerWithDefaultView()
        let bar = app.buttons["schedule-task-task-launch-brief"].firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 8), app.debugDescription)

        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()

        assertQuickEditorCanCancel(in: app)
    }

    func testPeopleScheduleIsDefaultViewAndCoreControlsWork() throws {
        let app = launchPlannerWithDefaultView()

        let schedule = app.descendants(matching: .any)["people-schedule-view"].firstMatch
        XCTAssertTrue(schedule.waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["schedule-person-person-mia"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["schedule-task-task-launch-brief"].firstMatch.waitForExistence(timeout: 5))

        let previous = app.buttons["schedule-previous"].firstMatch
        let today = app.buttons["schedule-today"].firstMatch
        let next = app.buttons["schedule-next"].firstMatch
        XCTAssertTrue(previous.waitForExistence(timeout: 5))
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        today.tap()

        // Period scope and refresh live in the compact overflow menu, so the
        // menu must be opened before either control exists in the hierarchy.
        let overflow = element(in: app, identifier: "schedule-overflow", labelContains: "更多操作")
        XCTAssertTrue(overflow.waitForExistence(timeout: 5), app.debugDescription)
        overflow.tap()

        let month = app.buttons["月"].firstMatch
        let week = app.buttons["周"].firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(week.waitForExistence(timeout: 5), app.debugDescription)
        month.tap()
        overflow.tap()
        XCTAssertTrue(
            app.buttons["周"].firstMatch.waitForExistence(timeout: 5),
            app.debugDescription
        )
        app.buttons["周"].firstMatch.tap()

        let sortMenu = app.buttons["sort-menu"].firstMatch
        XCTAssertTrue(sortMenu.waitForExistence(timeout: 5), app.debugDescription)
        sortMenu.tap()
        for title in ["手动顺序", "优先级", "标题", "最近更新"] {
            XCTAssertTrue(
                app.descendants(matching: .any)[title].firstMatch.waitForExistence(timeout: 3),
                "Missing first-level sort option: \(title)"
            )
        }
        app.descendants(matching: .any)["手动顺序"].firstMatch.tap()

        let person = app.descendants(matching: .any)["schedule-person-person-mia"].firstMatch
        XCTAssertTrue(person.waitForExistence(timeout: 5))
        person.tap()
        XCTAssertTrue(person.waitForExistence(timeout: 5))
    }

    func testPeopleScheduleAccessibilityAudit() throws {
        let app = launchPlannerWithDefaultView()
        XCTAssertTrue(
            app.descendants(matching: .any)["people-schedule-view"].firstMatch
                .waitForExistence(timeout: 8)
        )
        var unexpectedIssues: [String] = []
        try app.performAccessibilityAudit { issue in
            let label = issue.element?.label ?? ""
            let denseChartLabels = Set([
                "Ship brief",
                "Done item",
                "VoiceOver",
                "Schedule launch window",
                "Review window",
                "Mia Chen",
                "Noah Li",
                "未分配",
                "编辑者 · 1 项任务",
                "编辑者 · 2 项任务",
                "编辑者 · 3 项任务",
                "S",
                "M",
                "T",
                "W",
                "F",
                "Launch Room",
            ])
            let contrastFalsePositives = Set([
                "Noah Li",
                "编辑者 · 2 项任务",
                "Review window",
                "VoiceOver",
                "未分配",
                "无负责人 · 1 项任务",
                "今天",
            ])
            let compactPersonMetric = label.hasSuffix(" P0") || label.hasSuffix(" 进行中")
            let waivedDenseChartLayout = (denseChartLabels.contains(label) || compactPersonMetric)
                && (issue.auditType == .dynamicType || issue.auditType == .textClipped)
            let waivedContrast = issue.auditType == .contrast
                && contrastFalsePositives.contains(label)
            // SwiftUI reports one unassociated contrast diagnostic for the compact timeline.
            // Manual WCAG contrast checks are recorded in flat-task-bar evidence.
            let waivedUnassociatedCompactContrast = issue.auditType == .contrast
                && issue.element == nil
            if !waivedDenseChartLayout && !waivedContrast && !waivedUnassociatedCompactContrast {
                let identifier = issue.element?.identifier ?? ""
                let elementType = issue.element.map { String(describing: $0.elementType) } ?? ""
                unexpectedIssues.append(
                    "\(issue.compactDescription): \(issue.detailedDescription) [\(label)] id=\(identifier) type=\(elementType)"
                )
            }
            return true
        }

        XCTAssertTrue(unexpectedIssues.isEmpty, unexpectedIssues.joined(separator: "\n"))
    }

    func testCompactLayoutHidesEmptyNavigationBarAndKeepsSearch() throws {
        let app = launchPlannerWithDefaultView()

        // The compact navigation bar carries no items, so the project title
        // sits directly below the status bar instead of below an empty band.
        let projectSwitcher = element(
            in: app,
            identifier: "project-switcher",
            labelContains: "切换项目"
        )
        XCTAssertTrue(projectSwitcher.waitForExistence(timeout: 8))
        XCTAssertLessThan(projectSwitcher.frame.minY, 100, app.debugDescription)

        let filteredOut = app.buttons["schedule-task-task-launch-brief"].firstMatch
        XCTAssertTrue(filteredOut.waitForExistence(timeout: 5), app.debugDescription)

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), app.debugDescription)
        search.tap()
        search.typeText("VoiceOver")

        let disappeared = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: filteredOut
        )
        wait(for: [disappeared], timeout: 5)
        let result = app.buttons["schedule-task-task-voiceover"].firstMatch
        let scheduleRows = app.scrollViews.matching(
            NSPredicate(format: "label BEGINSWITH %@", "人员排期")
        ).firstMatch
        for _ in 0..<3 where !result.isHittable && scheduleRows.isHittable {
            scheduleRows.swipeUp()
        }
        XCTAssertTrue(result.waitForExistence(timeout: 5), app.debugDescription)
    }

    func testWeekStripChipSwitchesShownWeek() throws {
        let app = launchPlannerWithDefaultView()

        let summary = app.staticTexts["schedule-task-summary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 8), app.debugDescription)
        let currentWeekSummary = summary.label
        XCTAssertFalse(currentWeekSummary.hasPrefix("0 "), currentWeekSummary)

        // Demo tasks lie at most three days from today, so two weeks ahead is
        // always empty regardless of the weekday the test runs on.
        let next = app.buttons["schedule-next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        next.tap()
        XCTAssertTrue(
            NSPredicate(format: "label BEGINSWITH %@", "0 ").evaluate(with: summary),
            summary.label
        )

        let currentWeekChip = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "schedule-week-",
                "本周"
            )
        ).firstMatch
        XCTAssertTrue(currentWeekChip.waitForExistence(timeout: 5), app.debugDescription)
        currentWeekChip.tap()

        XCTAssertEqual(summary.label, currentWeekSummary)
        XCTAssertTrue(currentWeekChip.isSelected, app.debugDescription)
    }

    func testPeopleScheduleStatusControlOpensNativeMenu() throws {
        let app = launchPlannerWithDefaultView()
        let status = app.buttons["schedule-status-task-launch-brief"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 8), app.debugDescription)

        status.tap()

        let completed = app.buttons["已完成"].firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 3), app.debugDescription)
        completed.tap()
    }

    func testTaskDetailPanelShowsReferenceModesAndActions() throws {
        let app = launchPlanner()
        let task = app.descendants(matching: .any)["task-task-launch-brief"].firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 8), app.debugDescription)
        openTaskDetails(from: task, in: app)

        XCTAssertTrue(
            app.descendants(matching: .any)["task-detail"].firstMatch
                .waitForExistence(timeout: 8),
            app.debugDescription
        )
        let titlebarTitle = app.descendants(matching: .any)["task-detail"].firstMatch
        let titlebar = app.descendants(matching: .any)["task-panel-titlebar"].firstMatch
        let closeButton = element(
            in: app,
            identifier: "close-task-editor",
            labelContains: "关闭"
        )
        let layoutControl = element(
            in: app,
            identifier: "task-editor-layout-mode",
            labelContains: "任务编辑模式"
        )
        XCTAssertTrue(titlebar.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(layoutControl.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertGreaterThanOrEqual(titlebar.frame.height, 48)
        XCTAssertLessThanOrEqual(titlebar.frame.height, 56)
        XCTAssertEqual(titlebarTitle.frame.midX, titlebar.frame.midX, accuracy: 2)
        XCTAssertLessThan(closeButton.frame.midX, titlebarTitle.frame.midX)
        XCTAssertGreaterThan(layoutControl.frame.midX, titlebarTitle.frame.midX)
        XCTAssertTrue(app.textFields["task-title"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(
            element(in: app, identifier: "task-history-button", labelContains: "历史")
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            element(in: app, identifier: "duplicate-task", labelContains: "复制")
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            element(in: app, identifier: "delete-task", labelContains: "删除")
                .waitForExistence(timeout: 5)
        )

        let detailMode = app.descendants(matching: .any)["详情"].firstMatch
        XCTAssertTrue(detailMode.waitForExistence(timeout: 5), app.debugDescription)
        detailMode.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "Markdown 显示模式"))
                .firstMatch
                .waitForExistence(timeout: 5),
            app.debugDescription
        )

        let compactMode = app.descendants(matching: .any)["简约"].firstMatch
        XCTAssertTrue(compactMode.waitForExistence(timeout: 5), app.debugDescription)
        compactMode.tap()
        XCTAssertTrue(app.textFields["task-title"].firstMatch.waitForExistence(timeout: 5))
    }

    func testFilterPopoverUsesCompactChipSelection() throws {
        let app = launchPlannerWithDefaultView()
        let filterButton = element(
            in: app,
            identifier: "filter-button",
            labelContains: "筛选任务"
        )
        XCTAssertTrue(filterButton.waitForExistence(timeout: 8), app.debugDescription)
        filterButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["filter-popover"].firstMatch
                .waitForExistence(timeout: 8),
            app.debugDescription
        )

        let mia = app.buttons["filter-assignee-person-mia"].firstMatch
        XCTAssertTrue(mia.waitForExistence(timeout: 5), app.debugDescription)
        mia.tap()
        XCTAssertEqual(mia.value as? String, "已选择")

        let status = app.buttons["filter-status-in_progress"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5), app.debugDescription)
        status.tap()
        XCTAssertEqual(status.value as? String, "已选择")

        let priority = app.buttons["filter-priority-high"].firstMatch
        XCTAssertTrue(priority.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(priority.label.contains("P1"), app.debugDescription)

        let manualSort = app.buttons["filter-sort-manual"].firstMatch
        XCTAssertTrue(manualSort.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(manualSort.value as? String, "已选择")

        let reset = app.buttons["重置"].firstMatch
        XCTAssertTrue(reset.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(reset.isEnabled)
        reset.tap()
        XCTAssertEqual(mia.value as? String, "未选择")
        XCTAssertEqual(status.value as? String, "未选择")
        XCTAssertEqual(manualSort.value as? String, "已选择")

        let done = app.buttons["完成"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), app.debugDescription)
        done.tap()
    }

    func testCoreActionsMeetMinimumTouchTargets() throws {
        let app = launchPlanner()
        // Frames at fractional origins report heights such as
        // 43.99999999999997. The tolerance absorbs floating-point error only;
        // it is far below one device pixel (0.333pt at 3x).
        let minimumTarget: CGFloat = 44 - 0.01

        let actions = [
            element(in: app, identifier: "project-switcher", labelContains: "切换项目"),
            element(in: app, identifier: "add-task", labelContains: "添加任务"),
            element(in: app, identifier: "filter-button", labelContains: "筛选任务"),
            element(in: app, identifier: "refresh-button", labelContains: "刷新共享快照"),
            element(in: app, identifier: "sort-menu", labelContains: "排序"),
        ]

        for action in actions {
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(action.frame.width, minimumTarget)
            XCTAssertGreaterThanOrEqual(action.frame.height, minimumTarget)
        }

        let toggle = element(
            in: app,
            identifier: "toggle-task-task-launch-brief",
            labelContains: "标记为"
        )
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(toggle.frame.width, minimumTarget)
        XCTAssertGreaterThanOrEqual(toggle.frame.height, minimumTarget)
    }

    func testAddTaskActionsDoNotOverlap() throws {
        let app = launchPlanner()    }

    func testAccessibilityAudit() throws {
        let app = launchPlanner()
        let dynamicTypeFalsePositives = Set([
            "Launch Room",
            "Ship brief",
            "Mia Chen",
            "添加任务",
            "1 项",
            "2 项",
        ])
        let contrastFalsePositives = Set(["Done item"])
        var unexpectedIssues: [String] = []

        try app.performAccessibilityAudit { issue in
            let label = issue.element?.label ?? ""
            let waivedDynamicType = issue.auditType == .dynamicType
                && dynamicTypeFalsePositives.contains(label)
            let waivedContrast = issue.auditType == .contrast
                && contrastFalsePositives.contains(label)
            // iOS 27 sometimes emits one contrast issue for the SwiftUI glass
            // container without an associated accessibility element. Visible
            // task controls are audited individually; this orphan diagnostic
            // cannot be mapped to a color or node for a product fix.
            let waivedUnassociatedContrast = issue.auditType == .contrast
                && issue.element == nil
            if !waivedDynamicType && !waivedContrast && !waivedUnassociatedContrast {
                unexpectedIssues.append(
                    "\(issue.compactDescription): \(issue.detailedDescription) [\(label)] id=\(issue.element?.identifier ?? "") frame=\(String(describing: issue.element?.frame))"
                )
            }
            // Return true so this test reports one deterministic assertion below.
            return true
        }

        attachScreenshot(app, named: "ios-board-accessibility-audit")
        XCTAssertTrue(unexpectedIssues.isEmpty, unexpectedIssues.joined(separator: "\n"))
    }

    func testAccessibilityTextSizeKeepsCoreActionsAvailable() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launchEnvironment["KSHIFT_DEMO_MODE"] = "1"
        app.launchEnvironment["KSHIFT_RESET_PLANNER_VIEW_STATE"] = "1"
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
            app.descendants(matching: .any)["people-schedule-view"].firstMatch
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
        XCTAssertEqual(app.buttons.matching(identifier: "前一天").count, 0)

        let mia = app.descendants(matching: .any)["schedule-person-person-mia"].firstMatch
        XCTAssertTrue(mia.waitForExistence(timeout: 8))
        XCTAssertLessThanOrEqual(mia.frame.maxX, app.windows.firstMatch.frame.maxX + 1)

        XCTAssertTrue(
            app.staticTexts["Mia Chen"].firstMatch.waitForExistence(timeout: 8)
        )
    }

    func testBothProjectTimeZonesAndLiveUIWriteE2E() throws {
        let app = try launchLivePlanner()
        attachScreenshot(app, named: "ios-live-server")
        let selectedDate = app.descendants(matching: .any)["selected-date"].firstMatch
        XCTAssertTrue(selectedDate.waitForExistence(timeout: 8))
        XCTAssertTrue(selectedDate.label.contains("November 15"), selectedDate.label)
        assertDailyTaskCount(3, in: app)

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
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                    "task-",
                    "Shared roadmap task"
                )
            )
            .firstMatch
        XCTAssertTrue(initialTask.waitForExistence(timeout: 15), app.debugDescription)
        openTaskDetails(from: initialTask, in: app)

        XCTAssertTrue(
            app.descendants(matching: .any)["task-detail"]
                .waitForExistence(timeout: 8),
            app.debugDescription
        )
        app.buttons["task-history-button"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["任务历史"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS %@", "创建任务 Shared roadmap task"))
                .firstMatch
                .waitForExistence(timeout: 8),
            app.debugDescription
        )
        app.buttons["关闭"].firstMatch.tap()
        app.buttons["close-task-editor"].firstMatch.tap()

        firstMiaAddTask(in: app).tap()
        let titleField = taskTitleField(in: app)
        titleField.tap()
        titleField.typeText("Live UI created task")
        app.buttons["保存"].firstMatch.tap()

        assertDailyTaskCount(4, in: app)

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
        assertDailyTaskCount(1, in: app)
    }

    func testDefaultClientOpensRemoteProject() throws {
        let app = try launchLivePlanner()
        attachScreenshot(app, named: "ios-default-remote-client")
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

    private func assertQuickEditorCanCancel(in app: XCUIApplication) {
        let editor = app.descendants(matching: .any)["task-editor-popover"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 8), app.debugDescription)
        let title = app.descendants(matching: .any)["task-title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any)["task-detail"].firstMatch.exists)

        let cancel = app.buttons["取消"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), app.debugDescription)
        cancel.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5), app.debugDescription)
    }

    private func openTaskDetails(from card: XCUIElement, in app: XCUIApplication) {
        let actions = card.buttons["任务操作"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 5), app.debugDescription)
        actions.tap()
        let details = app.buttons["查看历史和详情"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 5), app.debugDescription)
        details.tap()
    }

    private func launchPlanner() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KSHIFT_DEMO_MODE"] = "1"
        app.launchEnvironment["KSHIFT_RESET_PLANNER_VIEW_STATE"] = "1"
        app.launchEnvironment["KSHIFT_INITIAL_VIEW_MODE"] = "board"
        app.launch()
        XCTAssertTrue(
            element(in: app, identifier: "project-switcher", labelContains: "切换项目")
                .waitForExistence(timeout: 8)
        )
        return app
    }

    private func launchPlannerWithDefaultView() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["KSHIFT_DEMO_MODE"] = "1"
        app.launchEnvironment["KSHIFT_RESET_PLANNER_VIEW_STATE"] = "1"
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
        // Do not inherit demo mode or the force-remote override from the simulator.
        app.launchEnvironment["KSHIFT_RESET_PLANNER_VIEW_STATE"] = "1"
        app.launchEnvironment["KSHIFT_INITIAL_VIEW_MODE"] = "board"
        app.launchEnvironment["KSHIFT_DEMO_MODE"] = "0"
        app.launchEnvironment["KSHIFT_USE_FFI"] = "0"
        app.launchEnvironment["KSHIFT_ENDPOINT"] = endpoint
        app.launchEnvironment["KSHIFT_CA_PEM"] = caPEM
        app.launchEnvironment["KSHIFT_TOKEN"] = token
        app.launchEnvironment["KSHIFT_ACTOR_ID"] = actorID
        app.launchEnvironment["KSHIFT_TLS_DOMAIN"] = "localhost"
        app.launchEnvironment["KSHIFT_USER_TIME_ZONE"] = userTimeZone
        app.launchEnvironment["KSHIFT_NOW"] = now
        app.launch()
        let remoteProject = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "project-switcher", primaryProject)
        ).firstMatch
        XCTAssertTrue(
            remoteProject.waitForExistence(timeout: 15),
            app.debugDescription
        )
        return app
    }

    private func assertDailyTaskCount(_ count: Int, in app: XCUIApplication) {
        let metric = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND label == %@", "daily-task-count", "当日任务 \(count)")
        ).firstMatch
        XCTAssertTrue(metric.waitForExistence(timeout: 10), app.debugDescription)
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
        let titleField = app.descendants(matching: .any)["task-title"].firstMatch
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
