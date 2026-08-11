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

    func testTagFilterShowsCleanTitlesAndNarrowsTheAgenda() {
        let app = launchDemo()

        let tagFilter = app.descendants(matching: .any)["event-tag-filter"]
        XCTAssertTrue(tagFilter.waitForExistence(timeout: 5), "tag filter")
        XCTAssertTrue(app.staticTexts["集中作業"].exists, "clean event title")
        XCTAssertFalse(app.staticTexts["集中作業 #仕事 #タスク"].exists, "raw tagged title must not leak into UI")
        XCTAssertTrue(app.descendants(matching: .any)["event-tag-chip-タスク"].exists, "tag chip")

        let taskFilter = app.buttons["event-tag-filter-タスク"]
        XCTAssertTrue(taskFilter.exists)
        taskFilter.tap()

        XCTAssertTrue(app.staticTexts["集中作業"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["歯科検診"].waitForNonExistence(timeout: 2))
        attachScreenshot(of: app, name: "Task tag filter")
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

    func testCreatesEstimatedTaskWithOneMonthEstimateAndTwoWeekBuffer() {
        let app = launchDemo()
        let addButton = app.buttons["add-calendar-item"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        app.buttons["見込みタスクを追加"].tap()

        let title = app.textFields["calendar-item-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertTrue(app.datePickers["calendar-item-estimated-center"].exists)
        XCTAssertTrue(app.steppers["calendar-item-estimated-buffer"].exists)
        XCTAssertTrue(app.staticTexts["目安日の前後：各2週間"].exists)
        attachScreenshot(of: app, name: "Estimated task editor")
        title.tap()
        title.typeText("特注指輪の刻印を確認")
        app.buttons["save-calendar-item"].tap()

        let created = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "特注指輪の刻印を確認")
        ).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 3))
        created.tap()
        XCTAssertTrue(app.staticTexts["見込み期間"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["中心の目安"].exists)
        attachScreenshot(of: app, name: "Estimated task window")
    }

    func testCreatesCompletesAndUndoesTask() {
        let app = launchDemo()
        let addButton = app.buttons["add-calendar-item"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()
        app.buttons["タスクを追加"].tap()

        let title = app.textFields["calendar-item-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        title.tap()
        title.typeText("請求書を送る")
        app.buttons["save-calendar-item"].tap()

        let createdTitle = app.staticTexts["請求書を送る"]
        XCTAssertTrue(createdTitle.waitForExistence(timeout: 3))
        createdTitle.tap()
        let complete = app.buttons["task-completion-button"]
        XCTAssertTrue(complete.waitForExistence(timeout: 2))
        complete.tap()
        XCTAssertTrue(app.buttons["undo-management-action"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["未完了に戻す"].exists)

        app.buttons["undo-management-action"].tap()
        XCTAssertTrue(app.buttons["タスクを完了"].waitForExistence(timeout: 2))
        attachScreenshot(of: app, name: "Task management")
    }

    func testEditsDuplicatesAndDeletesEvent() {
        let app = launchDemo()
        let event = app.staticTexts["歯科検診"]
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        event.tap()

        let edit = app.buttons["edit-calendar-item"]
        XCTAssertTrue(edit.waitForExistence(timeout: 2))
        edit.tap()
        let title = app.textFields["calendar-item-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        title.tap()
        title.clearAndType("歯科の定期検診")
        app.buttons["save-calendar-item"].tap()
        XCTAssertTrue(app.staticTexts["歯科の定期検診"].waitForExistence(timeout: 2))

        app.buttons["duplicate-calendar-item"].tap()
        XCTAssertTrue(app.buttons["save-calendar-item"].waitForExistence(timeout: 2))
        app.buttons["save-calendar-item"].tap()
        XCTAssertTrue(app.staticTexts["歯科の定期検診"].waitForExistence(timeout: 2))

        app.staticTexts["歯科の定期検診"].firstMatch.tap()
        let delete = app.buttons["delete-calendar-item"]
        XCTAssertTrue(delete.waitForExistence(timeout: 2))
        delete.tap()
        XCTAssertTrue(app.buttons["予定を削除"].waitForExistence(timeout: 2))
        app.buttons["予定を削除"].tap()
        XCTAssertTrue(app.staticTexts["歯科の定期検診"].waitForExistence(timeout: 2))
    }

    func testMutationFailuresAreAnnouncedInsidePresentedSheets() {
        let app = launchDemo(additionalArguments: ["-ui-testing-fail-mutations"])

        let task = app.staticTexts["集中作業"]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()
        let complete = app.buttons["task-completion-button"]
        XCTAssertTrue(complete.waitForExistence(timeout: 2))
        complete.tap()
        XCTAssertTrue(app.alerts["操作を完了できませんでした"].waitForExistence(timeout: 2))
        app.alerts.buttons["OK"].tap()
        app.buttons["閉じる"].tap()

        app.buttons["add-calendar-item"].tap()
        app.buttons["予定を追加"].tap()
        let title = app.textFields["calendar-item-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        title.tap()
        title.typeText("保存失敗を確認")
        app.buttons["save-calendar-item"].tap()
        XCTAssertTrue(app.alerts["保存できませんでした"].waitForExistence(timeout: 2))
    }

    func testFiltersOpenTasksAndSearchesCalendarContent() {
        let app = launchDemo()
        let openTasks = app.buttons["item-filter-openTasks"]
        XCTAssertTrue(openTasks.waitForExistence(timeout: 5))
        openTasks.tap()
        XCTAssertTrue(app.staticTexts["集中作業"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["歯科検診"].waitForNonExistence(timeout: 2))

        app.buttons["item-filter-all"].tap()
        let search = app.searchFields["予定・タスクを検索"]
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()
        search.typeText("歯科")
        XCTAssertTrue(app.staticTexts["歯科検診"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["集中作業"].waitForNonExistence(timeout: 2))
        attachScreenshot(of: app, name: "Search and management filters")
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

    private func launchDemo(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + additionalArguments
        app.launch()
        return app
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        tap()
        if let current = value as? String, !current.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
