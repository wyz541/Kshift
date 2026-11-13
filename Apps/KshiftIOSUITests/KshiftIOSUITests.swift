import XCTest

final class KshiftIOSUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCreateTaskThroughSharedPlanner() throws {
        let app = XCUIApplication()
        app.launch()

        let addTask = app.buttons.matching(
            NSPredicate(format: "label == %@", "为Mia Chen添加任务")
        ).firstMatch
        XCTAssertTrue(addTask.waitForExistence(timeout: 8))
        addTask.tap()

        let titleField = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ OR label == %@", "task-title", "任务标题"))
            .firstMatch
        if !titleField.waitForExistence(timeout: 5) {
            addTask.tap()
        }
        XCTAssertTrue(titleField.waitForExistence(timeout: 8))
        titleField.tap()
        titleField.typeText("UI evidence task")

        let save = app.buttons["保存"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(app.staticTexts["UI evidence task"].waitForExistence(timeout: 5))
    }
}
