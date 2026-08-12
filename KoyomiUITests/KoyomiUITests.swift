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

    func testDayViewKeepsAgendaVisibleWithoutScrolling() {
        let app = launchDemo()
        let dentist = app.staticTexts["歯科検診"]

        XCTAssertTrue(dentist.waitForExistence(timeout: 5))
        XCTAssertTrue(dentist.isHittable, "the selected day's agenda should be in the first viewport")
    }

    func testSecondaryFiltersLiveInDisplayOptionsSheet() {
        let app = launchDemo()

        XCTAssertFalse(app.descendants(matching: .any)["calendar-item-filter"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["event-tag-filter"].exists)

        let options = app.buttons["display-options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()

        XCTAssertTrue(app.buttons["item-filter-openTasks"].waitForExistence(timeout: 2))
        XCTAssertTrue(scrollToExistence(app.buttons["event-tag-filter-タスク"], in: app))
        XCTAssertTrue(scrollToExistence(app.buttons["calendar-toggle-demo-personal"], in: app))
    }

    func testPinnedEventsStartCompactAndExpandOnDemand() {
        let app = launchDemo()
        let summary = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "pin-summary-")
        ).firstMatch

        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "pin-card-")).count,
            0
        )

        app.buttons["pinned-section-toggle"].tap()
        let card = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "pin-card-")
        ).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 2))
        XCTAssertTrue(
            card.label.contains("あと"),
            "expanded pin must announce its countdown; label=\(card.label)"
        )
    }

    func testCompactControlsKeepMinimumTouchTargetsAndStateLabels() {
        let app = launchDemo()

        let pinToggle = app.buttons["pinned-section-toggle"]
        XCTAssertTrue(pinToggle.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(pinToggle.frame.height, 44)

        let datePicker = app.buttons["open-date-picker"]
        XCTAssertGreaterThanOrEqual(datePicker.frame.height, 44)
        XCTAssertTrue(
            datePicker.label.contains("日付を選ぶ") && datePicker.label.contains("8月"),
            "date picker must announce its action and visible month; label=\(datePicker.label)"
        )

        let tomorrow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "8月13日")
        ).firstMatch
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 2))
        tomorrow.tap()
        let today = app.buttons["今日へ移動"]
        XCTAssertTrue(today.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(today.frame.height, 44)

        app.buttons["show-calendar-search"].tap()
        let closeSearch = app.buttons["検索を終了"]
        XCTAssertTrue(closeSearch.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(closeSearch.frame.width, 44)
        XCTAssertGreaterThanOrEqual(closeSearch.frame.height, 44)
    }

    func testSearchAppearsOnlyWhenRequested() {
        let app = launchDemo()

        XCTAssertFalse(app.textFields["予定・タスクを検索"].exists)
        let searchButton = app.buttons["show-calendar-search"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        searchButton.tap()
        XCTAssertTrue(app.textFields["予定・タスクを検索"].waitForExistence(timeout: 2))
    }

    func testTagFilterShowsCleanTitlesAndNarrowsTheAgenda() {
        let app = launchDemo()

        XCTAssertTrue(app.staticTexts["集中作業"].exists, "clean event title")
        XCTAssertFalse(app.staticTexts["集中作業 #仕事 #タスク"].exists, "raw tagged title must not leak into UI")
        XCTAssertTrue(app.descendants(matching: .any)["event-tag-chip-タスク"].exists, "tag chip")

        app.buttons["display-options"].tap()
        let taskFilter = app.buttons["event-tag-filter-タスク"]
        XCTAssertTrue(scrollToExistence(taskFilter, in: app))
        taskFilter.tap()
        app.buttons["完了"].tap()

        XCTAssertTrue(app.staticTexts["集中作業"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["歯科検診"].waitForNonExistence(timeout: 2))
        let resetFilters = app.buttons["すべての絞り込みを解除"]
        XCTAssertTrue(resetFilters.waitForExistence(timeout: 2))
        XCTAssertGreaterThanOrEqual(resetFilters.frame.height, 44)
        attachScreenshot(of: app, name: "Task tag filter")
    }

    func testPinButtonAddsAnAgendaEventToPinnedEvents() {
        let app = launchDemo()
        let pinButton = app.buttons["agenda-pin-demo-release-week"]
        XCTAssertTrue(pinButton.waitForExistence(timeout: 5))
        if !pinButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(pinButton.isHittable, "pin button should be visible after scrolling")

        pinButton.tap()

        app.buttons["pinned-section-toggle"].tap()
        let pinScroll = app.scrollViews["pinned-cards-scroll"]
        XCTAssertTrue(pinScroll.waitForExistence(timeout: 5))
        let remove = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "pin-remove-",
                "リリース週"
            )
        ).firstMatch
        for _ in 0..<4 where !remove.exists {
            pinScroll.swipeLeft()
        }
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["プロジェクト発表"].exists, "removing one pin must keep the other pin")
    }

    func testDetailPinToggleUsesTheLatestCalendarRevision() {
        let app = launchDemo()
        let dentist = app.staticTexts["歯科検診"]
        XCTAssertTrue(dentist.waitForExistence(timeout: 5))
        dentist.tap()

        let pin = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "event-detail-pin-toggle",
                "この予定をピン留め"
            )
        ).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 2))
        pin.tap()

        let unpin = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS %@",
                "event-detail-pin-toggle",
                "ピン留めを解除"
            )
        ).firstMatch
        XCTAssertTrue(unpin.waitForExistence(timeout: 2))
        unpin.tap()

        XCTAssertTrue(pin.waitForExistence(timeout: 2))
    }

    func testRecurringPinChangeAsksForOccurrenceScope() {
        let app = launchDemo(additionalArguments: ["-ui-testing-recurring-pin"])
        let recurringRow = app.buttons["agenda-event-demo-daily-pin"]
        XCTAssertTrue(scrollToExistence(recurringRow, in: app))
        recurringRow.tap()

        let toggle = app.buttons["event-detail-pin-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        toggle.tap()

        XCTAssertTrue(app.staticTexts["ピン留めを変更する範囲"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["この予定のみ"].exists)
        XCTAssertTrue(app.buttons["これ以降すべて"].exists)
        XCTAssertTrue(toggle.exists, "範囲を選ぶまではCalendarを変更しない")
    }

    func testRecurringExpandedPinRemovalAsksForOccurrenceScope() {
        let app = launchDemo(additionalArguments: ["-ui-testing-recurring-pin"])
        let section = app.buttons["pinned-section-toggle"]
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        section.tap()

        let pinScroll = app.scrollViews["pinned-cards-scroll"]
        XCTAssertTrue(pinScroll.waitForExistence(timeout: 2))
        let remove = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "pin-remove-",
                "毎日の確認"
            )
        ).firstMatch
        for _ in 0..<6 where !remove.exists {
            pinScroll.swipeLeft()
        }
        XCTAssertTrue(remove.waitForExistence(timeout: 2))
        remove.tap()

        XCTAssertTrue(app.staticTexts["ピン留めを変更する範囲"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["この予定のみ"].exists)
        XCTAssertTrue(app.buttons["これ以降すべて"].exists)
        XCTAssertTrue(remove.exists, "範囲を選ぶまではCalendarを変更しない")
    }

    func testDetailPinFailureAppearsInsideTheDetailSheet() {
        let app = launchDemo(additionalArguments: ["-ui-testing-fail-mutations"])
        let dentist = app.staticTexts["歯科検診"]
        XCTAssertTrue(dentist.waitForExistence(timeout: 5))
        dentist.tap()

        let pin = app.buttons["event-detail-pin-toggle"]
        XCTAssertTrue(pin.waitForExistence(timeout: 2))
        pin.tap()

        let alert = app.alerts["操作を完了できませんでした"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        XCTAssertTrue(alert.staticTexts["ピン留めを変更できませんでした。予定の最新状態を確認してください。"].exists)
    }

    func testReadOnlyPinnedEventDoesNotExposeImpossiblePinControls() {
        let app = launchDemo(additionalArguments: ["-ui-testing-read-only-pin"])
        let dentist = app.staticTexts["歯科検診"]
        XCTAssertTrue(dentist.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["agenda-pin-demo-dentist"].exists)

        let dentistAgendaRow = app.buttons["agenda-event-demo-dentist"]
        XCTAssertTrue(dentistAgendaRow.exists)
        dentistAgendaRow.tap()
        XCTAssertFalse(app.buttons["event-detail-pin-toggle"].exists)
        XCTAssertTrue(app.staticTexts["このCalendarは読み取り専用です。閲覧のみ利用できます。"].exists)
        app.buttons["閉じる"].tap()

        app.buttons["pinned-section-toggle"].tap()
        XCTAssertFalse(
            app.buttons.matching(
                NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                    "pin-remove-",
                    "歯科検診"
                )
            ).firstMatch.exists
        )
    }

    func testCalendarFilterCanHideOneDeviceCalendar() {
        let app = launchDemo()
        let filterButton = app.buttons["display-options"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5))

        filterButton.tap()
        let personalCalendar = app.buttons["calendar-toggle-demo-personal"]
        XCTAssertTrue(scrollToExistence(personalCalendar, in: app))
        XCTAssertTrue(personalCalendar.isSelected)
        attachScreenshot(of: app, name: "Calendar filter")
        personalCalendar.tap()
        XCTAssertFalse(personalCalendar.isSelected)
        app.buttons["完了"].tap()

        XCTAssertTrue(app.staticTexts["歯科検診"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["集中作業"].waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["カレンダー 1/2"].waitForExistence(timeout: 2))
    }

    func testUpcomingViewShowsFutureEventsGroupedByDate() {
        let app = launchDemo()
        app.buttons["display-options"].tap()
        let upcomingButton = app.segmentedControls.buttons["予定一覧"]
        XCTAssertTrue(upcomingButton.waitForExistence(timeout: 5))

        upcomingButton.tap()
        app.buttons["完了"].tap()

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
        let centerDatePicker = app.datePickers["calendar-item-estimated-center"]
        XCTAssertTrue(centerDatePicker.exists)
        let allVisibleElements = app.descendants(matching: .any)
        XCTAssertEqual(
            allVisibleElements.matching(NSPredicate(format: "label CONTAINS %@", "Reiwa")).count,
            0
        )
        XCTAssertTrue(app.steppers["calendar-item-estimated-buffer"].exists)
        XCTAssertTrue(app.staticTexts["目安日の前後：各2週間"].exists)
        attachScreenshot(of: app, name: "Estimated task editor")
        title.tap()
        title.typeText("特注指輪の刻印を確認")
        app.buttons["save-calendar-item"].tap()

        app.buttons["pinned-section-toggle"].tap()
        let created = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                "pin-card-",
                "特注指輪の刻印を確認"
            )
        ).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout: 3))
        created.tap()
        XCTAssertTrue(app.staticTexts["見込み期間"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["中心の目安"].exists)
        attachScreenshot(of: app, name: "Estimated task window")
    }

    func testTagEditorUsesSuggestionsAndRemovableChips() {
        let app = launchDemo()
        app.buttons["add-calendar-item"].tap()
        app.buttons["予定を追加"].tap()

        let title = app.textFields["calendar-item-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        title.tap()
        title.typeText("家族でランチ")

        let workSuggestion = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ AND label == %@",
                "calendar-item-tag-suggestion",
                "タグ、仕事を追加"
            )
        ).firstMatch
        XCTAssertTrue(scrollToExistence(workSuggestion, in: app))
        let suggestionRail = app.scrollViews["calendar-item-tag-suggestions-scroll"]
        XCTAssertTrue(suggestionRail.exists)
        XCTAssertLessThanOrEqual(
            suggestionRail.frame.height,
            56,
            "候補は縦に肥大化せず1段で横スクロールできる"
        )
        workSuggestion.tap()

        let selectedWork = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ AND label == %@",
                "calendar-item-tag-selected",
                "タグ、仕事を削除"
            )
        ).firstMatch
        XCTAssertTrue(selectedWork.waitForExistence(timeout: 2))
        XCTAssertEqual(selectedWork.value as? String, "選択中")
        XCTAssertTrue(app.staticTexts["タップで外す"].exists)

        let input = app.textFields["calendar-item-tag-input"]
        XCTAssertTrue(input.exists)
        let addTag = app.buttons["calendar-item-tag-add"]
        XCTAssertFalse(addTag.isEnabled)
        XCTAssertEqual(addTag.value as? String, "タグ名を入力")
        XCTAssertGreaterThanOrEqual(addTag.frame.height, 44)
        input.tap()
        input.typeText("家族")
        XCTAssertTrue(addTag.isEnabled)
        XCTAssertEqual(addTag.value as? String, "追加できます")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2))
        XCTAssertLessThanOrEqual(
            addTag.frame.maxY,
            keyboard.frame.minY,
            "キーボード表示中も追加ボタン全体をタップできる"
        )
        addTag.tap()
        let selectedFamily = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ AND label == %@",
                "calendar-item-tag-selected",
                "タグ、家族を削除"
            )
        ).firstMatch
        XCTAssertTrue(selectedFamily.waitForExistence(timeout: 2))

        selectedWork.tap()
        XCTAssertTrue(selectedWork.waitForNonExistence(timeout: 2))
        XCTAssertTrue(workSuggestion.waitForExistence(timeout: 2), "外したタグは候補からすぐ戻せる")

        let navigationBar = app.navigationBars.firstMatch
        XCTAssertTrue(navigationBar.exists)
        XCTAssertGreaterThanOrEqual(
            selectedFamily.frame.minY,
            navigationBar.frame.maxY + 4,
            "キーボードを閉じた後も選択済みタグがtoolbarの下へ潜らない"
        )
        attachScreenshot(of: app, name: "Tag editor chips")

        app.buttons["save-calendar-item"].tap()
        let created = app.staticTexts["家族でランチ"]
        XCTAssertTrue(created.waitForExistence(timeout: 3))
        created.tap()
        XCTAssertTrue(app.descendants(matching: .any)["event-tag-chip-家族"].waitForExistence(timeout: 2))
    }

    func testTagEditorKeepsLongTagsInsideTheScreenAtAccessibilityTextSize() {
        let app = launchDemo(
            additionalArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL"
            ]
        )
        app.buttons["add-calendar-item"].tap()
        app.buttons["予定を追加"].tap()

        let input = app.textFields["calendar-item-tag-input"]
        XCTAssertTrue(scrollToExistence(input, in: app))
        input.tap()
        input.typeText("とても長いプロジェクト名でも安全に編集できるタグ")
        app.buttons["calendar-item-tag-add"].tap()

        let chip = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ AND label == %@",
                "calendar-item-tag-selected",
                "タグ、とても長いプロジェクト名でも安全に編集できるタグを削除"
            )
        ).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(
            chip.frame.height,
            44,
            "Accessibility XXXLでは44pt固定ではなく、文字の実寸に合わせて縦へ拡張する"
        )
        XCTAssertGreaterThanOrEqual(chip.frame.minX, app.windows.firstMatch.frame.minX + 16)
        XCTAssertLessThanOrEqual(chip.frame.maxX, app.windows.firstMatch.frame.maxX - 16)
    }

    func testCompletionTagMovesToVisibleTaskStateWhenKindChanges() {
        let app = launchDemo()
        app.buttons["add-calendar-item"].tap()
        app.buttons["予定を追加"].tap()

        let title = app.textFields["calendar-item-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        title.tap()
        title.typeText("完了済みの記録")

        let input = app.textFields["calendar-item-tag-input"]
        XCTAssertTrue(scrollToExistence(input, in: app))
        input.tap()
        input.typeText("完了")
        app.buttons["calendar-item-tag-add"].tap()
        let selectedCompletedTag = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ AND label == %@",
                "calendar-item-tag-selected",
                "タグ、完了を削除"
            )
        ).firstMatch
        XCTAssertTrue(selectedCompletedTag.waitForExistence(timeout: 2))

        let taskKind = app.segmentedControls.buttons["タスク"]
        for _ in 0..<6 where !taskKind.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(taskKind.isHittable)
        taskKind.tap()

        let completed = app.switches["完了"]
        XCTAssertTrue(completed.waitForExistence(timeout: 2), "完了状態を専用Toggleで確認できる")
        XCTAssertEqual(completed.value as? String, "1")
        XCTAssertTrue(selectedCompletedTag.waitForNonExistence(timeout: 2))

        app.segmentedControls.buttons["予定"].tap()
        XCTAssertTrue(scrollToExistence(selectedCompletedTag, in: app))
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
        app.buttons["display-options"].tap()
        let openTasks = app.buttons["item-filter-openTasks"]
        XCTAssertTrue(openTasks.waitForExistence(timeout: 5))
        openTasks.tap()
        XCTAssertTrue(openTasks.isSelected)
        app.buttons["完了"].tap()
        XCTAssertTrue(app.staticTexts["集中作業"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["歯科検診"].waitForNonExistence(timeout: 2))

        app.buttons["display-options"].tap()
        app.buttons["item-filter-all"].tap()
        app.buttons["完了"].tap()
        app.buttons["show-calendar-search"].tap()
        let search = app.textFields["予定・タスクを検索"]
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
