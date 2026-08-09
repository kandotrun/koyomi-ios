import XCTest

final class KoyomiUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDemoShowsPinnedCountdownAndDailyAgenda() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.staticTexts["こよみ"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["pinned-section"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["プロジェクト発表"].exists)
        XCTAssertTrue(app.otherElements["date-strip"].exists)
        XCTAssertTrue(app.otherElements["agenda-list"].exists)
        XCTAssertTrue(app.staticTexts["歯科検診"].exists)
        XCTAssertTrue(app.buttons["歯科検診をピン留め"].exists)
    }
}
