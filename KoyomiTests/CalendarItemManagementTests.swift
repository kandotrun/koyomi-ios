import Foundation
import Testing
@testable import KoyomiCore

@Suite("予定とタスクの管理契約")
struct CalendarItemManagementTests {
    @Test("タスク・完了・重要をタグから判定する")
    func derivesTaskStateFromTags() {
        let task = makeEvent(title: "請求書を送る #タスク #重要 #完了")
        let event = makeEvent(title: "顧客定例 #仕事")

        #expect(task.managementKind == .task)
        #expect(task.isCompletedTask)
        #expect(task.isImportantItem)
        #expect(event.managementKind == .event)
        #expect(!event.isCompletedTask)
    }

    @Test("完了にしても元タイトルの空白と未知タグを保持する")
    func completingTaskPreservesUntouchedTitleBytes() {
        let raw = "  請求書  を送る   #タスク  #顧客A\n"

        let updated = EventTitleTagMutator.applying(
            EventTitleTagChange(adding: ["完了"], removing: []),
            to: raw
        )

        #expect(updated == "  請求書  を送る   #タスク  #顧客A\n#完了")
    }

    @Test("未完了へ戻すと完了タグだけを消す")
    func reopeningTaskRemovesOnlyCompletionTag() {
        let raw = "請求書を送る #タスク  #完了 #顧客A"

        let updated = EventTitleTagMutator.applying(
            EventTitleTagChange(adding: [], removing: ["完了"]),
            to: raw
        )

        #expect(updated == "請求書を送る #タスク   #顧客A")
        #expect(EventTitleMetadata.parse(updated).tags == ["タスク", "顧客A"])
    }

    @Test("表記揺れを重複追加せず対象タグだけ削除する")
    func normalizesTagIdentityForDiffs() {
        let raw = "設計 #ＴＡＳＫ #ProjectX #done"

        let updated = EventTitleTagMutator.applying(
            EventTitleTagChange(
                adding: ["task", "重要", "重要"],
                removing: ["DONE"]
            ),
            to: raw
        )

        #expect(updated == "設計 #ＴＡＳＫ #ProjectX #重要")
        #expect(EventTitleMetadata.parse(updated).tags == ["ＴＡＳＫ", "ProjectX", "重要"])
    }

    @Test("タグ削除時も直後の句読点を保持する")
    func removingTagPreservesPunctuationSuffix() {
        let updated = EventTitleTagMutator.applying(
            EventTitleTagChange(adding: [], removing: ["タスク"]),
            to: "確認 #タスク, #顧客A"
        )

        #expect(updated == "確認 , #顧客A")
    }

    @Test("予定名を変更しても未知タグの表記と句読点を保持する")
    func replacingReadableTextPreservesRawTagTokens() {
        let updated = EventTitleTagMutator.replacingReadableText(
            in: "  旧  タイトル   #ProjectX,  #顧客A\n",
            with: "新しいタイトル"
        )

        #expect(updated == "新しいタイトル #ProjectX, #顧客A")
    }

    @Test("非タスク予定の完了タグはcustom tagとして保持する")
    func preservesCompletedTagOnOrdinaryEvent() {
        let event = CalendarEvent(
            id: "event",
            eventIdentifier: "event",
            externalIdentifier: nil,
            title: "振り返り #完了 #個人",
            startDate: Date(timeIntervalSince1970: 1_750_000_000),
            endDate: Date(timeIntervalSince1970: 1_750_003_600),
            isAllDay: false,
            calendarID: "personal",
            calendarName: "個人",
            calendarColorHex: "21A179",
            location: nil
        )

        #expect(CalendarItemDraft(event).tags == ["完了", "個人"])
    }

    @Test("再発タスクのUndoは直前と同じ変更範囲を保持する")
    func completionUndoPreservesMutationScope() {
        let action = CalendarCompletionUndoAction(
            previousCompletedValue: false,
            scope: .futureEvents
        )

        #expect(action.previousCompletedValue == false)
        #expect(action.scope == .futureEvents)
    }

    @Test("終日予定の排他的終了日を画面上の最終日に変換する")
    func convertsAllDayExclusiveEndForEditing() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7)))
        let exclusiveEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)))
        let expectedDisplayEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9)))

        let displayEnd = CalendarAllDayRange.displayEndDate(
            forExclusiveEnd: exclusiveEnd,
            startDate: start,
            calendar: calendar
        )
        let roundTripEnd = CalendarAllDayRange.exclusiveEndDate(
            forDisplayEnd: displayEnd,
            startDate: start,
            calendar: calendar
        )

        #expect(displayEnd == expectedDisplayEnd)
        #expect(roundTripEnd == exclusiveEnd)
    }

    @Test("繰り返し曜日の選択状態をVoiceOver向けに明示する")
    func describesWeekdaySelectionForAccessibility() {
        #expect(CalendarRecurrenceAccessibility.selectionValue(isSelected: false) == "未選択")
        #expect(CalendarRecurrenceAccessibility.selectionValue(isSelected: true) == "選択済み")
    }

    @Test("これ以降の削除は同じseriesの境界以降のピンだけを除く")
    func removesFuturePinsForDeletedRecurringSeries() {
        let current = makeEvent(title: "定例 #仕事")
        var past = current
        past.startDate = current.startDate.addingTimeInterval(-86_400)
        past.endDate = current.endDate.addingTimeInterval(-86_400)
        past.id = EventOccurrenceID.make(
            eventIdentifier: past.eventIdentifier,
            externalIdentifier: past.externalIdentifier,
            startDate: past.startDate
        )
        var future = current
        future.startDate = current.startDate.addingTimeInterval(86_400)
        future.endDate = current.endDate.addingTimeInterval(86_400)
        future.id = EventOccurrenceID.make(
            eventIdentifier: future.eventIdentifier,
            externalIdentifier: future.externalIdentifier,
            startDate: future.startDate
        )
        let unrelated = makeEvent(title: "別の予定 #仕事")
        var unrelatedPin = unrelated.pinnedSnapshot
        unrelatedPin.id = "unrelated"
        unrelatedPin.eventIdentifier = "other-series"
        unrelatedPin.externalIdentifier = "other-external"

        let remaining = PinnedEventDeletionPolicy.remainingPins(
            afterDeleting: current,
            scope: .futureEvents,
            from: [past.pinnedSnapshot, current.pinnedSnapshot, future.pinnedSnapshot, unrelatedPin]
        )

        #expect(remaining.map(\.id) == [past.pinnedSnapshot.id, unrelatedPin.id])
    }

    @Test("日跨ぎ予定は開始日と終了日の両方を表示する")
    func summarizesMultiDayTimedEvent() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 11, hour: 23, minute: 30
        )))
        let end = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 12, hour: 1, minute: 0
        )))
        var event = makeEvent(title: "日跨ぎ #仕事")
        event.startDate = start
        event.endDate = end

        let summary = CalendarItemDateSummary.text(
            for: event,
            calendar: calendar,
            locale: Locale(identifier: "ja_JP")
        )

        #expect(summary == "2026年8月11日 23:30〜2026年8月12日 1:00")
    }

    @Test("複数日の終日予定は実際の最終日を表示する")
    func summarizesMultiDayAllDayEventUsingInclusiveDisplayEnd() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 11)))
        let exclusiveEnd = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 14)))
        var event = makeEvent(title: "休暇 #休み")
        event.startDate = start
        event.endDate = exclusiveEnd
        event.isAllDay = true

        let summary = CalendarItemDateSummary.text(
            for: event,
            calendar: calendar,
            locale: Locale(identifier: "ja_JP")
        )

        #expect(summary == "2026年8月11日〜2026年8月13日・終日")
    }

    @Test("アラームは順序が違っても同じ設定と判定する")
    func comparesAlarmOffsetsAsAMultiset() {
        #expect(CalendarAlarmOffsets.equivalent([0, -900, -1_800], [-1_800, 0, -900]))
        #expect(!CalendarAlarmOffsets.equivalent([0, -900], [-900]))
    }

    @Test("Koyomiで完全表現できない再発ルールは編集時に原形を保持する")
    func preservesUnsupportedRecurrenceRuleDuringEditorSave() {
        let advanced = CalendarRecurrenceRule(
            frequency: .monthly,
            interval: 1,
            weekdays: [.tuesday],
            endDate: nil,
            occurrenceCount: nil,
            isFullyRepresentable: false
        )

        let saved = CalendarRecurrenceEditorPolicy.ruleForSave(
            original: advanced,
            frequency: .monthly,
            interval: 1,
            weekdays: [],
            endDate: nil,
            occurrenceCount: nil
        )

        #expect(saved == advanced)
    }

    @Test("旧形式の再発ルールは完全表現可能として復元する")
    func decodesLegacyRecurrenceRule() throws {
        let data = Data(#"{"frequency":"monthly","interval":1,"weekdays":[]}"#.utf8)
        let recurrence = try JSONDecoder().decode(CalendarRecurrenceRule.self, from: data)

        #expect(recurrence.isFullyRepresentable)
    }

    @Test("週次繰り返しの要約に選択曜日を含める")
    func summarizesWeeklyRecurrenceWeekdays() {
        let recurrence = CalendarRecurrenceRule(
            frequency: .weekly,
            weekdays: [.monday, .wednesday, .friday]
        )

        #expect(CalendarRecurrenceSummary.text(recurrence) == "毎週（月・水・金）")
    }

    @Test("目安日と前後バッファをDSTをまたぐ見込み期間へ変換する")
    func buildsEstimatedWindowAcrossDaylightSavingTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Sofia"))
        let center = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25)))
        let expectedStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 11)))
        let expectedLatest = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 8)))

        let window = try #require(
            CalendarEstimatedWindow.centered(on: center, bufferDays: 14, calendar: calendar)
        )

        #expect(window.centerDate == center)
        #expect(window.startDate == expectedStart)
        #expect(window.latestDate == expectedLatest)
        #expect(window.bufferDays == 14)
    }

    @Test("見込み期間をEventKit互換の終日帯と予約タグで往復する")
    func roundTripsEstimatedWindowThroughCalendarEvent() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let center = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 11)))
        let window = try #require(
            CalendarEstimatedWindow.centered(on: center, bufferDays: 14, calendar: calendar)
        )
        let title = ManagedCalendarTitle.make(
            readableTitle: "指輪の刻印が完了",
            kind: .task,
            dateMode: .estimatedWindow,
            isImportant: true,
            isCompleted: false,
            tags: ["ブルガリア", "見込み"]
        )
        var event = makeEvent(title: title)
        event.startDate = window.startDate
        event.endDate = window.endDate
        event.isAllDay = true

        let restored = try #require(CalendarEstimatedWindow(event: event, calendar: calendar))
        let restoredPin = try #require(
            CalendarEstimatedWindow(event: event.pinnedSnapshot, calendar: calendar)
        )
        let draft = CalendarItemDraft(event)

        #expect(title == "指輪の刻印が完了 #タスク #見込み #重要 #ブルガリア")
        #expect(event.isEstimatedDateWindow)
        #expect(restored.centerDate == center)
        #expect(restored.bufferDays == 14)
        #expect(restoredPin == restored)
        #expect(draft.dateMode == .estimatedWindow)
        #expect(draft.tags == ["ブルガリア"])
    }

    @Test("見込み期間の保存形状はタスク・終日・非反復・左右対称に限定する")
    func validatesEstimatedWindowDraftShape() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let center = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 11)))
        let window = try #require(
            CalendarEstimatedWindow.centered(on: center, bufferDays: 14, calendar: calendar)
        )
        let valid = CalendarItemDraft(
            kind: .task,
            dateMode: .estimatedWindow,
            readableTitle: "海外加工",
            startDate: window.startDate,
            endDate: window.endDate,
            isAllDay: true,
            calendarID: "work"
        )
        var eventKind = valid
        eventKind.kind = .event
        var timed = valid
        timed.isAllDay = false
        var recurring = valid
        recurring.recurrence = CalendarRecurrenceRule(frequency: .monthly)
        var asymmetric = valid
        asymmetric.endDate = try #require(calendar.date(byAdding: .day, value: -1, to: valid.endDate))

        #expect(valid.hasValidDateModeShape(calendar: calendar))
        #expect(!eventKind.hasValidDateModeShape(calendar: calendar))
        #expect(!timed.hasValidDateModeShape(calendar: calendar))
        #expect(!recurring.hasValidDateModeShape(calendar: calendar))
        #expect(!asymmetric.hasValidDateModeShape(calendar: calendar))
    }

    @Test("見込みタグだけの通常予定は任意タグとして保持する")
    func keepsEstimatedTagCustomOutsideManagedTasks() {
        var event = makeEvent(title: "納期の候補 #見込み #仕事")
        event.isAllDay = true
        event.endDate = event.startDate.addingTimeInterval(29 * 86_400)

        let draft = CalendarItemDraft(event)

        #expect(!event.isEstimatedDateWindow)
        #expect(draft.dateMode == .exact)
        #expect(draft.tags == ["見込み", "仕事"])
    }

    @Test("見込みタグ付きでも単日タスクは任意タグとして保持する")
    func keepsEstimatedTagCustomWithoutWindowGeometry() {
        var event = makeEvent(title: "候補日 #タスク #見込み")
        event.isAllDay = true
        event.endDate = event.startDate.addingTimeInterval(86_400)

        let draft = CalendarItemDraft(event)

        #expect(!event.isEstimatedDateWindow)
        #expect(draft.dateMode == .exact)
        #expect(draft.tags == ["見込み"])
    }

    @Test("見込み表示は和英混在せず中心・幅・期間を明示する")
    func formatsEstimatedWindowInConsistentJapaneseGregorianDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let center = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 11)))
        let window = try #require(
            CalendarEstimatedWindow.centered(on: center, bufferDays: 14, calendar: calendar)
        )

        #expect(CalendarEstimatedWindowText.date(window.centerDate, calendar: calendar) == "2026年9月11日")
        #expect(CalendarEstimatedWindowText.range(window, calendar: calendar) == "2026年8月28日〜9月25日")
        #expect(CalendarEstimatedWindowText.buffer(days: 14) == "各2週間")
        #expect(CalendarEstimatedWindowText.width(window) == "幅4週間")
    }

    @Test("見込み期間の状態は開始前・期間中・期限超過を区別する")
    func presentsEstimatedWindowStatusWithoutFalsePrecision() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let center = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 11)))
        let window = try #require(
            CalendarEstimatedWindow.centered(on: center, bufferDays: 14, calendar: calendar)
        )
        let before = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 12)))
        let inside = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 12)))
        let overdue = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12)))

        #expect(window.status(at: before, calendar: calendar) == .upcoming(daysUntilStart: 14))
        #expect(window.status(at: inside, calendar: calendar) == .withinWindow(daysUntilLatest: 14))
        #expect(window.status(at: overdue, calendar: calendar) == .overdue(days: 3))
    }

    @Test("新規タスクのタイトルは管理タグを一度だけ付与する")
    func buildsNewTaskTitleWithoutDuplicateManagementTags() {
        let title = ManagedCalendarTitle.make(
            readableTitle: "  旅行を予約  ",
            kind: .task,
            isImportant: true,
            isCompleted: false,
            tags: ["旅行", "タスク", "重要", "旅行"]
        )

        #expect(title == "旅行を予約 #タスク #重要 #旅行")
    }

    private func makeEvent(title: String) -> CalendarEvent {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        return CalendarEvent(
            id: "occurrence",
            eventIdentifier: "event",
            externalIdentifier: "external",
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            isAllDay: false,
            calendarID: "work",
            calendarName: "仕事",
            calendarColorHex: "5B8DEF",
            location: nil
        )
    }
}
