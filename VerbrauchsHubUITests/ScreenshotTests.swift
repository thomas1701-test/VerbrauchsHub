import XCTest

/// Generates App Store screenshots with demo data.
/// Run on a fresh install; attachments are exported from the .xcresult bundle.
@MainActor
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-seedDemoData", "-licenseSimulate", "unlocked", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
    }

    func testScreenshots() throws {
        let tabs = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch : nil
        func tab(_ name: String) {
            // iPad exposes each tab twice (tab bar + sidebar), so take the first match.
            let button = (tabs?.buttons[name] ?? app.buttons[name]).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 5), "Tab \(name) missing")
            button.tap()
        }

        // 1 — Dashboard
        XCTAssertTrue(app.staticTexts["Strom (Bezug)"].firstMatch.waitForExistence(timeout: 10))
        sleep(3) // the launch zoom animation is still running on first start
        snap("01-dashboard")

        // 7 — Annual goal and billing forecast (uploaded as second image)
        app.staticTexts["Strom (Bezug)"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Jahresabrechnung"].waitForExistence(timeout: 5))
        snap("07-billing")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 2 — Meter detail
        XCTAssertTrue(app.staticTexts["Gas"].firstMatch.waitForExistence(timeout: 5))
        app.staticTexts["Gas"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Verlauf"].waitForExistence(timeout: 5))
        snap("02-detail")

        // 3 — New reading sheet
        app.buttons["Ablesung hinzufügen"].tap()
        let field = app.textFields["Zählerstand"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("21612,8")
        snap("03-reading")
        app.buttons["Abbrechen"].tap()

        // 4 — Statistics, filtered to "Mein Haus" electricity meters with previous-year comparison
        tab("Statistik")
        let switcher = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Alle'")).firstMatch
        if switcher.waitForExistence(timeout: 3) {
            switcher.tap()
            app.buttons["Mein Haus"].firstMatch.tap()
        }
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Alle Zähler'")).firstMatch.tap()
        for name in ["Strom (Bezug)", "PV-Einspeisung", "PV-Eigenverbrauch"] {
            // Scope to the filter sheet's list; the page behind it shows the same names.
            app.collectionViews.staticTexts[name].firstMatch.tap()
        }
        app.buttons["Fertig"].tap()
        snap("04-statistics")

        // 5 — PV energy balance further down
        app.swipeUp()
        snap("05-pv")

        // 6 — Meter list grouped by building
        tab("Zähler")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Mein Haus'")).firstMatch.tap()
        app.buttons["Alle Gebäude"].firstMatch.tap()
        snap("06-meters")
    }

    private func snap(_ name: String) {
        sleep(1) // let charts finish animating
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
