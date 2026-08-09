import XCTest

@MainActor
final class KoyomiUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDemoShowsPinnedCountdownAndDailyAgenda() {
        let app = launchDemo()

        XCTAssertTrue(app.staticTexts["こよみ"].waitForExistence(timeout: 5), "navigation title")
        XCTAssertTrue(app.descendants(matching: .any)["pinned-section"].waitForExistence(timeout: 2), "pinned section")
        XCTAssertTrue(app.staticTexts["プロジェクト発表"].exists, "seeded pinned event")
        XCTAssertTrue(app.descendants(matching: .any)["month-title"].exists, "month and year context")
        XCTAssertTrue(app.descendants(matching: .any)["date-strip"].exists, "date strip")
        XCTAssertTrue(app.descendants(matching: .any)["agenda-list"].exists, "agenda list")
        XCTAssertTrue(app.staticTexts["歯科検診"].exists, "demo agenda event")
        XCTAssertTrue(app.buttons["歯科検診をピン留め"].exists, "pin action")
    }

    func testPinButtonAddsAnAgendaEventToPinnedEvents() {
        let app = launchDemo()
        let pinButton = app.buttons["歯科検診をピン留め"]
        XCTAssertTrue(pinButton.waitForExistence(timeout: 5))

        pinButton.tap()

        XCTAssertTrue(app.buttons["歯科検診のピン留めを解除"].waitForExistence(timeout: 2))
    }

    private func launchDemo() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        return app
    }
}
