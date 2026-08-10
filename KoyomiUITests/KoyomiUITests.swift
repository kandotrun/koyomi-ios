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
        if !pinButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(pinButton.isHittable, "pin button should be visible after scrolling")

        pinButton.tap()

        XCTAssertTrue(app.buttons["歯科検診のピン留めを解除"].waitForExistence(timeout: 5))
    }

    func testCalendarFilterCanHideOneDeviceCalendar() {
        let app = launchDemo()
        let filterButton = app.buttons["表示するカレンダーを選ぶ"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5))

        filterButton.tap()
        let personalCalendar = app.buttons["calendar-toggle-demo-personal"]
        XCTAssertTrue(personalCalendar.waitForExistence(timeout: 2))
        attachScreenshot(of: app, name: "Calendar filter")
        personalCalendar.tap()
        app.buttons["完了"].tap()

        XCTAssertTrue(app.staticTexts["歯科検診"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["集中作業"].waitForNonExistence(timeout: 2))
    }

    func testUpcomingViewShowsFutureEventsGroupedByDate() {
        let app = launchDemo()
        let upcomingButton = app.segmentedControls.buttons["予定一覧"]
        XCTAssertTrue(upcomingButton.waitForExistence(timeout: 5))

        upcomingButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["upcoming-list"].waitForExistence(timeout: 2))
        let travelEvent = app.descendants(matching: .any)["upcoming-event-demo-travel"]
        XCTAssertTrue(scrollToExistence(travelEvent, in: app))
        XCTAssertTrue(app.staticTexts["新幹線の予約"].exists)
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "令和")).count,
            0,
            "future date headings should be short and scan-friendly"
        )
        attachScreenshot(of: app, name: "Upcoming events")
    }

    private func scrollToExistence(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.exists { return true }
        for _ in 0..<6 {
            app.swipeUp()
            if element.waitForExistence(timeout: 0.5) { return true }
        }
        return false
    }

    private func attachScreenshot(of app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launchDemo() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        return app
    }
}
