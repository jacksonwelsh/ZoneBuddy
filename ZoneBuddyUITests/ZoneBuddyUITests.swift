import XCTest

final class ZoneBuddyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    /// Tap the "New Workout" toolbar button, handling the Menu variant when Apple Intelligence is available.
    private func tapNewWorkout() {
        app.navigationBars["Workouts"].buttons["New Workout"].tap()
        let createManually = app.buttons["Create Manually"]
        if createManually.waitForExistence(timeout: 1) {
            createManually.tap()
        }
    }

    @MainActor
    func testWorkoutLibraryShowsOnLaunch() throws {
        XCTAssertTrue(app.navigationBars["Workouts"].exists)
    }

    @MainActor
    func testCreateNewWorkout() throws {
        tapNewWorkout()

        XCTAssertTrue(app.navigationBars["Edit Workout"].waitForExistence(timeout: 2))

        let nameField = app.textFields["Workout Name"]
        XCTAssertTrue(nameField.exists)
    }

    @MainActor
    func testAddIntervalToWorkout() throws {
        tapNewWorkout()
        _ = app.navigationBars["Edit Workout"].waitForExistence(timeout: 2)

        app.buttons["Add"].tap()

        XCTAssertTrue(app.navigationBars["Add Interval"].waitForExistence(timeout: 2))

        app.navigationBars["Add Interval"].buttons["Add"].tap()

        XCTAssertTrue(app.staticTexts["Zone 3"].waitForExistence(timeout: 2))
    }
}
