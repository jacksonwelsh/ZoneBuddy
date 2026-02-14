import XCTest

final class WorkoutCreationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    @MainActor
    func testFullWorkoutCreationFlow() throws {
        // Create a new workout
        app.navigationBars["Workouts"].buttons["New Workout"].tap()
        _ = app.navigationBars["Edit Workout"].waitForExistence(timeout: 2)

        // Rename the workout
        let nameField = app.textFields["Workout Name"]
        nameField.tap()
        nameField.clearAndTypeText("My PZ Ride")

        // Add an interval
        app.buttons["Add"].tap()
        _ = app.navigationBars["Add Interval"].waitForExistence(timeout: 2)
        app.navigationBars["Add Interval"].buttons["Add"].tap()

        // Verify interval appears
        XCTAssertTrue(app.staticTexts["Zone 3"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testStartRideButtonDisabledWithNoIntervals() throws {
        app.navigationBars["Workouts"].buttons["New Workout"].tap()
        _ = app.navigationBars["Edit Workout"].waitForExistence(timeout: 2)

        let startButton = app.buttons["Start Ride"]
        XCTAssertTrue(startButton.exists)
        XCTAssertFalse(startButton.isEnabled)
    }
}

extension XCUIElement {
    func clearAndTypeText(_ text: String) {
        guard let stringValue = self.value as? String else {
            XCTFail("Tried to clear a non-string value")
            return
        }

        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: stringValue.count)
        self.typeText(deleteString)
        self.typeText(text)
    }
}
