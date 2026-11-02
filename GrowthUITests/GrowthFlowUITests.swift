import XCTest

final class GrowthFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
    }

    func testDeletingGoalReturnsToTheList() {
        createGoal(type: "milestone", title: "Delete me", extra: nil)
        openGoal("Delete me")
        app.buttons["goal.menu"].tap()
        let delete = app.buttons["goal.delete"]
        if delete.waitForExistence(timeout: 2) {
            delete.tap()
        } else {
            app.buttons["Delete goal"].tap()
        }
        XCTAssertTrue(app.navigationBars["Goals"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars["Delete me"].exists)
    }

    func testEachGoalTypeJournalAndRecalibrate() {
        createGoal(type: "milestone", title: "Write the essay", extra: nil)
        openGoal("Write the essay")
        app.buttons["Plan"].tap()
        app.buttons["plan.addPhase"].tap()
        let phaseField = app.alerts.textFields.firstMatch
        XCTAssertTrue(phaseField.waitForExistence(timeout: 2))
        phaseField.typeText("Draft")
        app.alerts.buttons["Add"].tap()
        app.buttons["Add checkpoint"].tap()
        let checkpointField = app.alerts.textFields.firstMatch
        XCTAssertTrue(checkpointField.waitForExistence(timeout: 2))
        checkpointField.typeText("Outline")
        app.alerts.buttons["Add"].tap()
        app.buttons["checkpoint.toggle.Outline"].tap()
        let complete = app.alerts["Mark complete?"]
        XCTAssertTrue(complete.waitForExistence(timeout: 2))
        complete.buttons["Mark complete"].tap()
        app.buttons["Overview"].tap()
        let completed = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Complete")).firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        createGoal(type: "project", title: "Ship the talk", extra: nil)
        openGoal("Ship the talk")
        XCTAssertTrue(app.buttons["Plan"].waitForExistence(timeout: 2))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        createGoal(type: "numeric", title: "Savings", extra: {
            let start = self.app.textFields["goal.numericStart"]
            let target = self.app.textFields["goal.numericTarget"]
            start.tap()
            start.typeText("0")
            target.tap()
            target.typeText("10")
        })
        openGoal("Savings")
        app.buttons["overview.updateValue"].tap()
        let value = app.textFields["progress.value"]
        XCTAssertTrue(value.waitForExistence(timeout: 2))
        value.tap()
        value.typeText("10")
        app.buttons["progress.save"].tap()
        let reached = app.alerts["Mark complete?"]
        XCTAssertTrue(reached.waitForExistence(timeout: 2))
        reached.buttons["Not now"].tap()
        XCTAssertTrue(app.staticTexts["10 of 10"].waitForExistence(timeout: 2))
        app.buttons["Add milestones"].tap()
        XCTAssertTrue(app.buttons["plan.addPhase"].waitForExistence(timeout: 2))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        createGoal(type: "habit", title: "Morning walk", extra: nil)
        openGoal("Morning walk")
        XCTAssertFalse(app.buttons["Plan"].exists)
        app.buttons["overview.logHabit"].tap()
        app.buttons["habit.save"].tap()
        XCTAssertTrue(app.staticTexts["In progress"].waitForExistence(timeout: 2))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons["Journal"].tap()
        app.buttons["journal.new"].tap()
        let title = app.textFields["journal.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        title.tap()
        title.typeText("A quiet note")
        app.buttons["journal.save"].tap()
        XCTAssertTrue(app.staticTexts["A quiet note"].waitForExistence(timeout: 2))
    }

    private func createGoal(type: String, title: String, extra: (() -> Void)?) {
        app.tabBars.buttons["Goals"].tap()
        if app.buttons["goals.new"].waitForExistence(timeout: 2) {
            app.buttons["goals.new"].tap()
        } else {
            app.buttons["New goal"].tap()
        }
        app.buttons["goalType.\(type)"].tap()
        let titleField = app.textFields["goal.title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.tap()
        titleField.typeText(title)
        extra?()
        app.buttons["goal.save"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
    }

    private func openGoal(_ title: String) {
        app.tabBars.buttons["Goals"].tap()
        let query = app.staticTexts.matching(NSPredicate(format: "label == %@", title))
        let element = query.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? query.firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        element.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 2))
    }
}
