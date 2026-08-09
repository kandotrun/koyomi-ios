import XCTest

@MainActor
final class KoyomiUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDemoShowsPinnedCountdownAndDailyAgenda() {
        let app = launchDemo()

        XCTAssertTrue(app.staticTexts["こよみ"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["pinned-section"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["プロジェクト発表"].exists)
        XCTAssertTrue(app.otherElements["date-strip"].exists)
        XCTAssertTrue(app.otherElements["agenda-list"].exists)
        XCTAssertTrue(app.staticTexts["歯科検診"].exists)
        XCTAssertTrue(app.buttons["歯科検診をピン留め"].exists)
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
