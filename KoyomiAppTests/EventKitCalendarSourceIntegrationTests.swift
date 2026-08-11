import EventKit
import XCTest
@testable import Koyomi

@MainActor
final class EventKitCalendarSourceIntegrationTests: XCTestCase {
    func testTaskRoundTripAndConflictFailClosed() async throws {
        let store = EKEventStore()
        let granted = try await store.requestFullAccessToEvents()
        try XCTSkipUnless(granted, "Calendar full access is required")

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Koyomi Integration \(UUID().uuidString)"
        calendar.source = try XCTUnwrap(
            store.sources.first(where: { $0.sourceType == .local })
                ?? store.defaultCalendarForNewEvents?.source
        )
        try store.saveCalendar(calendar, commit: true)
        defer { try? store.removeCalendar(calendar, commit: true) }

        let source = EventKitCalendarSource(eventStore: store)
        let start = Date().addingTimeInterval(7_200)
        let draft = CalendarItemDraft(
            kind: .task,
            readableTitle: "統合テスト",
            startDate: start,
            endDate: start.addingTimeInterval(1_800),
            isAllDay: false,
            calendarID: calendar.calendarIdentifier,
            tags: ["未知タグ"],
            isImportant: true,
            notes: "削除される一時データ",
            alarmOffsets: [-900]
        )

        let created = try source.createItem(draft)
        XCTAssertEqual(created.managementKind, .task)
        XCTAssertFalse(created.isCompletedTask)
        XCTAssertEqual(created.notes, "削除される一時データ")
        XCTAssertEqual(created.alarmOffsets, [-900])
        XCTAssertTrue(created.canEdit)

        let completed = try source.setTaskCompletion(
            created,
            completed: true,
            scope: .thisEvent
        )
        XCTAssertTrue(completed.isCompletedTask)
        XCTAssertTrue(completed.titleMetadata.containsTag("未知タグ"))

        let external = try XCTUnwrap(store.event(withIdentifier: completed.eventIdentifier))
        external.title = "外部で変更 #タスク"
        try store.save(external, span: .thisEvent, commit: true)

        XCTAssertThrowsError(
            try source.setTaskCompletion(completed, completed: false, scope: .thisEvent)
        ) { error in
            XCTAssertEqual(error as? CalendarEventSourceError, .conflict)
        }
        XCTAssertEqual(
            store.event(withIdentifier: completed.eventIdentifier)?.title,
            "外部で変更 #タスク"
        )

        let refreshed = try XCTUnwrap(
            try source.events(
                in: DateInterval(
                    start: start.addingTimeInterval(-60),
                    end: start.addingTimeInterval(3_600)
                ),
                calendarIDs: [calendar.calendarIdentifier]
            ).first
        )
        try source.deleteItem(refreshed, scope: .thisEvent)
        XCTAssertTrue(
            try source.events(
                in: DateInterval(
                    start: start.addingTimeInterval(-60),
                    end: start.addingTimeInterval(3_600)
                ),
                calendarIDs: [calendar.calendarIdentifier]
            ).isEmpty
        )
    }

    func testUnrelatedEditPreservesAbsoluteAlarmSemantics() async throws {
        let store = EKEventStore()
        let granted = try await store.requestFullAccessToEvents()
        try XCTSkipUnless(granted, "Calendar full access is required")

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Koyomi Alarm \(UUID().uuidString)"
        calendar.source = try XCTUnwrap(
            store.sources.first(where: { $0.sourceType == .local })
                ?? store.defaultCalendarForNewEvents?.source
        )
        try store.saveCalendar(calendar, commit: true)
        defer { try? store.removeCalendar(calendar, commit: true) }

        let start = Date().addingTimeInterval(10_800)
        let absoluteAlarmDate = start.addingTimeInterval(-1_800)
        let rawEvent = EKEvent(eventStore: store)
        rawEvent.calendar = calendar
        rawEvent.title = "絶対時刻アラーム #仕事"
        rawEvent.startDate = start
        rawEvent.endDate = start.addingTimeInterval(3_600)
        rawEvent.alarms = [
            EKAlarm(absoluteDate: absoluteAlarmDate),
            EKAlarm(relativeOffset: -900)
        ]
        try store.save(rawEvent, span: .thisEvent, commit: true)

        let source = EventKitCalendarSource(eventStore: store)
        let loaded = try XCTUnwrap(
            try source.events(
                in: DateInterval(
                    start: start.addingTimeInterval(-60),
                    end: start.addingTimeInterval(3_660)
                ),
                calendarIDs: [calendar.calendarIdentifier]
            ).first
        )
        var editorEvent = loaded
        editorEvent.alarmOffsets = [0, -900]
        var draft = CalendarItemDraft(editorEvent)
        draft.alarmOffsets.sort()
        draft.notes = "メモだけ変更"

        let updated = try source.updateItem(editorEvent, with: draft, scope: .thisEvent)
        let persisted = try XCTUnwrap(store.event(withIdentifier: updated.eventIdentifier))
        let persistedAlarms = try XCTUnwrap(persisted.alarms)
        let persistedAlarm = try XCTUnwrap(persistedAlarms.first(where: { $0.absoluteDate != nil }))

        XCTAssertEqual(persistedAlarms.count, 2)
        XCTAssertTrue(persistedAlarms.contains { $0.absoluteDate == nil && $0.relativeOffset == -900 })
        XCTAssertEqual(
            try XCTUnwrap(persistedAlarm.absoluteDate).timeIntervalSinceReferenceDate,
            absoluteAlarmDate.timeIntervalSinceReferenceDate,
            accuracy: 0.5
        )

        var replacementDraft = CalendarItemDraft(updated)
        replacementDraft.alarmOffsets = [-300]
        XCTAssertThrowsError(
            try source.updateItem(updated, with: replacementDraft, scope: .thisEvent)
        ) { error in
            guard case CalendarEventSourceError.unsupported = error else {
                return XCTFail("Expected unsupported, got \(error)")
            }
        }
    }

    func testDateEndedRecurrenceDoesNotBecomeZeroCount() async throws {
        let store = EKEventStore()
        let granted = try await store.requestFullAccessToEvents()
        try XCTSkipUnless(granted, "Calendar full access is required")

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Koyomi Date End \(UUID().uuidString)"
        calendar.source = try XCTUnwrap(
            store.sources.first(where: { $0.sourceType == .local })
                ?? store.defaultCalendarForNewEvents?.source
        )
        try store.saveCalendar(calendar, commit: true)
        defer { try? store.removeCalendar(calendar, commit: true) }

        let start = Date().addingTimeInterval(7_200)
        let endDate = start.addingTimeInterval(5 * 86_400)
        let rawEvent = EKEvent(eventStore: store)
        rawEvent.calendar = calendar
        rawEvent.title = "日付終了の再発"
        rawEvent.startDate = start
        rawEvent.endDate = start.addingTimeInterval(3_600)
        rawEvent.recurrenceRules = [
            EKRecurrenceRule(
                recurrenceWith: .daily,
                interval: 1,
                end: EKRecurrenceEnd(end: endDate)
            )
        ]
        try store.save(rawEvent, span: .thisEvent, commit: true)

        let source = EventKitCalendarSource(eventStore: store)
        let loaded = try XCTUnwrap(
            try source.events(
                in: DateInterval(start: start.addingTimeInterval(-60), end: endDate),
                calendarIDs: [calendar.calendarIdentifier]
            ).first
        )

        XCTAssertNotNil(loaded.recurrence?.endDate)
        XCTAssertNil(loaded.recurrence?.occurrenceCount)
    }

    func testEstimatedWindowRoundTripsThroughEventKit() async throws {
        let store = EKEventStore()
        let granted = try await store.requestFullAccessToEvents()
        try XCTSkipUnless(granted, "Calendar full access is required")

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Koyomi Estimated \(UUID().uuidString)"
        calendar.source = try XCTUnwrap(
            store.sources.first(where: { $0.sourceType == .local })
                ?? store.defaultCalendarForNewEvents?.source
        )
        try store.saveCalendar(calendar, commit: true)
        defer { try? store.removeCalendar(calendar, commit: true) }

        var dateCalendar = Calendar(identifier: .gregorian)
        dateCalendar.timeZone = .current
        let center = try XCTUnwrap(
            dateCalendar.date(byAdding: .month, value: 1, to: dateCalendar.startOfDay(for: Date()))
        )
        let window = try XCTUnwrap(
            CalendarEstimatedWindow.centered(on: center, bufferDays: 14, calendar: dateCalendar)
        )
        let source = EventKitCalendarSource(eventStore: store)
        let created = try source.createItem(
            CalendarItemDraft(
                kind: .task,
                dateMode: .estimatedWindow,
                readableTitle: "指輪の刻印が完了",
                startDate: window.startDate,
                endDate: window.endDate,
                isAllDay: true,
                calendarID: calendar.calendarIdentifier,
                tags: ["ブルガリア"]
            )
        )

        XCTAssertTrue(created.isEstimatedDateWindow)
        XCTAssertEqual(created.titleMetadata.tags, ["タスク", "見込み", "ブルガリア"])
        XCTAssertEqual(created.startDate, window.startDate)
        XCTAssertEqual(created.endDate, window.endDate)
        XCTAssertEqual(CalendarItemDraft(created).dateMode, .estimatedWindow)
    }

    func testAdvancedMonthlyRecurrenceSurvivesUnrelatedEditorSave() async throws {
        let store = EKEventStore()
        let granted = try await store.requestFullAccessToEvents()
        try XCTSkipUnless(granted, "Calendar full access is required")

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Koyomi Advanced Recurrence \(UUID().uuidString)"
        calendar.source = try XCTUnwrap(
            store.sources.first(where: { $0.sourceType == .local })
                ?? store.defaultCalendarForNewEvents?.source
        )
        try store.saveCalendar(calendar, commit: true)
        defer { try? store.removeCalendar(calendar, commit: true) }

        let dateCalendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(
            dateCalendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 10))
        )
        let rawEvent = EKEvent(eventStore: store)
        rawEvent.calendar = calendar
        rawEvent.title = "第2火曜の定例"
        rawEvent.startDate = start
        rawEvent.endDate = start.addingTimeInterval(3_600)
        rawEvent.recurrenceRules = [
            EKRecurrenceRule(
                recurrenceWith: .monthly,
                interval: 1,
                daysOfTheWeek: [EKRecurrenceDayOfWeek(.tuesday, weekNumber: 2)],
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            )
        ]
        try store.save(rawEvent, span: .thisEvent, commit: true)

        let source = EventKitCalendarSource(eventStore: store)
        let loaded = try XCTUnwrap(
            try source.events(
                in: DateInterval(
                    start: start.addingTimeInterval(-60),
                    end: start.addingTimeInterval(3_660)
                ),
                calendarIDs: [calendar.calendarIdentifier]
            ).first
        )
        XCTAssertEqual(loaded.recurrence?.isFullyRepresentable, false)

        var draft = CalendarItemDraft(loaded)
        draft.notes = "メモだけ変更"
        draft.recurrence = CalendarRecurrenceEditorPolicy.ruleForSave(
            original: draft.recurrence,
            frequency: draft.recurrence?.frequency,
            interval: draft.recurrence?.interval ?? 1,
            weekdays: [],
            endDate: draft.recurrence?.endDate,
            occurrenceCount: draft.recurrence?.occurrenceCount
        )

        let updated = try source.updateItem(loaded, with: draft, scope: .futureEvents)
        let persisted = try XCTUnwrap(store.event(withIdentifier: updated.eventIdentifier))
        let persistedRule = try XCTUnwrap(persisted.recurrenceRules?.first)
        let persistedDay = try XCTUnwrap(persistedRule.daysOfTheWeek?.first)
        XCTAssertEqual(persistedDay.dayOfTheWeek, .tuesday)
        XCTAssertEqual(persistedDay.weekNumber, 2)

        var destructiveDraft = CalendarItemDraft(updated)
        destructiveDraft.recurrence = CalendarRecurrenceRule(frequency: .monthly)
        XCTAssertThrowsError(
            try source.updateItem(updated, with: destructiveDraft, scope: .thisEvent)
        ) { error in
            guard case CalendarEventSourceError.unsupported = error else {
                return XCTFail("Expected unsupported, got \(error)")
            }
        }
    }

    func testFutureScopeOnlyChangesSelectedAndLaterOccurrences() async throws {
        let store = EKEventStore()
        let granted = try await store.requestFullAccessToEvents()
        try XCTSkipUnless(granted, "Calendar full access is required")

        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Koyomi Recurrence \(UUID().uuidString)"
        calendar.source = try XCTUnwrap(
            store.sources.first(where: { $0.sourceType == .local })
                ?? store.defaultCalendarForNewEvents?.source
        )
        try store.saveCalendar(calendar, commit: true)
        defer { try? store.removeCalendar(calendar, commit: true) }

        let source = EventKitCalendarSource(eventStore: store)
        let start = try XCTUnwrap(
            Calendar.current.date(
                bySettingHour: 9,
                minute: 0,
                second: 0,
                of: Date().addingTimeInterval(86_400)
            )
        )
        _ = try source.createItem(
            CalendarItemDraft(
                kind: .task,
                readableTitle: "再発テスト",
                startDate: start,
                endDate: start.addingTimeInterval(1_800),
                isAllDay: false,
                calendarID: calendar.calendarIdentifier,
                recurrence: CalendarRecurrenceRule(
                    frequency: .daily,
                    occurrenceCount: 3
                )
            )
        )
        let interval = DateInterval(
            start: start.addingTimeInterval(-60),
            end: start.addingTimeInterval(4 * 86_400)
        )
        let occurrences = try source.events(
            in: interval,
            calendarIDs: [calendar.calendarIdentifier]
        ).sorted { $0.startDate < $1.startDate }
        XCTAssertEqual(occurrences.count, 3)

        _ = try source.setTaskCompletion(
            occurrences[1],
            completed: true,
            scope: .futureEvents
        )

        let refreshed = try source.events(
            in: interval,
            calendarIDs: [calendar.calendarIdentifier]
        ).sorted { $0.startDate < $1.startDate }
        XCTAssertEqual(refreshed.count, 3)
        XCTAssertFalse(refreshed[0].isCompletedTask)
        XCTAssertTrue(refreshed[1].isCompletedTask)
        XCTAssertTrue(refreshed[2].isCompletedTask)
    }
}
