import XCTest

final class ZoneBuddyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    @MainActor
    func testWorkoutLibraryShowsOnLaunch() throws {
        XCTAssertTrue(app.navigationBars["Workouts"].exists)
    }

    @MainActor
    func testCreateNewWorkout() throws {
        app.navigationBars["Workouts"].buttons["New Workout"].tap()

        XCTAssertTrue(app.navigationBars["Edit Workout"].waitForExistence(timeout: 2))

        let nameField = app.textFields["Workout Name"]
        XCTAssertTrue(nameField.exists)
    }

    @MainActor
    func testAddIntervalToWorkout() throws {
        app.navigationBars["Workouts"].buttons["New Workout"].tap()
        _ = app.navigationBars["Edit Workout"].waitForExistence(timeout: 2)

        app.buttons["Add"].tap()

        XCTAssertTrue(app.navigationBars["Add Interval"].waitForExistence(timeout: 2))

        app.navigationBars["Add Interval"].buttons["Add"].tap()

        XCTAssertTrue(app.staticTexts["Zone 3"].waitForExistence(timeout: 2))
    }
}
