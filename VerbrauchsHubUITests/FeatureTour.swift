import XCTest

/// Walks through the 1.1 features and attaches screenshots (manual check, not part of CI).
@MainActor
final class FeatureTour: XCTestCase {
    func testTour() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["-seedDemoData", "-licenseSimulate", "unlocked", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Strom (Bezug)"].firstMatch.waitForExistence(timeout: 10))
        app.staticTexts["Strom (Bezug)"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Jahresabrechnung"].waitForExistence(timeout: 5))
        snap("detail-top")
        app.swipeUp()
        snap("detail-scrolled")

        // Edit a reading
        app.swipeUp()
        app.descendants(matching: .any).matching(identifier: "readingRow").firstMatch.tap()
        if app.navigationBars["Ablesung bearbeiten"].waitForExistence(timeout: 3) {
            snap("edit-reading")
            app.buttons["Abbrechen"].tap()
        } else {
            snap("edit-reading-missing")
        }

        // Edit meter (secondary toolbar action may sit in an overflow menu)
        app.swipeDown()
        app.swipeDown()
        let edit = app.buttons["Zähler bearbeiten"]
        if edit.waitForExistence(timeout: 3) {
            edit.tap()
            XCTAssertTrue(app.navigationBars["Zähler bearbeiten"].waitForExistence(timeout: 3))
            snap("edit-meter")
            app.buttons["Abbrechen"].tap()
        } else {
            snap("edit-meter-missing")
        }

        // New reading with plausibility warning
        app.buttons["Ablesung hinzufügen"].tap()
        let field = app.textFields["Zählerstand"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("999999")
        app.buttons["Speichern"].tap()
        if app.alerts.firstMatch.waitForExistence(timeout: 3) {
            snap("plausibility")
            app.alerts.buttons["Korrigieren"].tap()
        }
        app.buttons["Abbrechen"].tap()

        // Gas detail (billing period from April, seasonal forecast)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["Gas"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Jahresabrechnung"].waitForExistence(timeout: 5))
        snap("gas-detail")
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
