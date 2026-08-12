import Foundation
import XCTest
@testable import KoyomiCore

final class WidgetTimelinePlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testCreatesUniqueBoundaryEntriesAndReevaluatesVisiblePins() {
        let first = pin(id: "first", start: now.addingTimeInterval(100), end: now.addingTimeInterval(200))
        let second = pin(id: "second", start: now.addingTimeInterval(100), end: now.addingTimeInterval(300))
        let ended = pin(id: "ended", start: now.addingTimeInterval(-200), end: now.addingTimeInterval(-100))

        let states = WidgetTimelinePlanner.states(from: [second, ended, first], at: now, limit: 3)

        XCTAssertEqual(states.map(\.date), [
            now,
            now.addingTimeInterval(102),
            now.addingTimeInterval(202),
            now.addingTimeInterval(302)
        ])
        XCTAssertEqual(states[0].pins.map(\.id), ["first", "second"])
        XCTAssertEqual(states[1].pins.map(\.id), ["first", "second"])
        XCTAssertEqual(states[2].pins.map(\.id), ["second"])
        XCTAssertEqual(states[3].pins, [])
    }

    func testNoPinsProducesOnlyTheCurrentEntry() {
        XCTAssertEqual(
            WidgetTimelinePlanner.states(from: [], at: now, limit: 3),
            [WidgetTimelineState(date: now, pins: [])]
        )
    }

    func testZeroLimitProducesOnlyTheCurrentEntry() {
        let future = pin(
            id: "future",
            start: now.addingTimeInterval(20),
            end: now.addingTimeInterval(30)
        )

        XCTAssertEqual(
            WidgetTimelinePlanner.states(from: [future], at: now, limit: 0),
            [WidgetTimelineState(date: now, pins: [])]
        )
    }

    func testNegativeTransitionOffsetIsClampedToZero() {
        let future = pin(
            id: "future",
            start: now.addingTimeInterval(10),
            end: now.addingTimeInterval(20)
        )

        XCTAssertEqual(WidgetTimelinePlanner.normalizedTransitionOffset(-1), 0)
        XCTAssertEqual(
            WidgetTimelinePlanner.states(
                from: [future],
                at: now,
                limit: 1,
                transitionOffset: -1
            ).map(\.date),
            [now, now.addingTimeInterval(10), now.addingTimeInterval(20)]
        )
    }

    func testCapsTimelineEntryCountAtAPlannedBoundary() {
        let futurePins = (1...100).map { index in
            pin(
                id: "future-\(index)",
                start: now.addingTimeInterval(TimeInterval(index * 10)),
                end: now.addingTimeInterval(TimeInterval(index * 10 + 5))
            )
        }

        let states = WidgetTimelinePlanner.states(
            from: futurePins,
            at: now,
            limit: 1,
            transitionOffset: 0,
            maximumEntryCount: 4
        )

        XCTAssertEqual(WidgetTimelinePlanner.defaultMaximumEntryCount, 64)
        XCTAssertEqual(states.count, 4)
        XCTAssertEqual(
            states.map(\.date),
            [
                now,
                now.addingTimeInterval(10),
                now.addingTimeInterval(15),
                now.addingTimeInterval(20)
            ]
        )
    }

    func testNonPositiveMaximumEntryCountKeepsOnlyTheCurrentEntry() {
        let future = pin(
            id: "future",
            start: now.addingTimeInterval(10),
            end: now.addingTimeInterval(20)
        )

        XCTAssertEqual(
            WidgetTimelinePlanner.states(
                from: [future],
                at: now,
                limit: 1,
                maximumEntryCount: 0
            ),
            [WidgetTimelineState(date: now, pins: [future])]
        )
    }

    func testContinuesIndefiniteDailySeriesAfterCachedThirtySecondOccurrence() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstStart = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let events = try (0..<64).map { offset in
            let start = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: firstStart))
            return CalendarEvent(
                id: "daily-\(offset)",
                eventIdentifier: "daily-event-\(offset)",
                externalIdentifier: "daily-series",
                title: "毎日の確認 #ピン",
                startDate: start,
                endDate: start.addingTimeInterval(3_600),
                isAllDay: false,
                calendarID: "personal",
                calendarName: "個人",
                calendarColorHex: "21A179",
                location: nil,
                recurrence: CalendarRecurrenceRule(frequency: .daily),
                recurrenceTimeZoneIdentifier: "Asia/Tokyo",
                isRecurring: true,
                canEdit: true
            )
        }
        let validationInterval = DateInterval(
            start: firstStart,
            end: events.last!.endDate
        )
        let snapshots = CalendarPin.snapshots(
            from: events,
            at: now,
            recurrenceValidationInterval: validationInterval,
            calendar: calendar
        )
        let lastCached = events[CalendarPin.maximumRecurringOccurrencesPerSeries - 1]
        let expectedStart = events[CalendarPin.maximumRecurringOccurrencesPerSeries].startDate
        let states = WidgetTimelinePlanner.states(
            from: snapshots,
            at: lastCached.endDate.addingTimeInterval(1),
            limit: 1,
            transitionOffset: 0
        )

        XCTAssertTrue(
            states.contains { state in
                state.pins.contains { $0.startDate == expectedStart }
            },
            "アプリを再度開かなくてもWidgetは33件目以降をCalendar由来の再発ルールから継続する"
        )
    }

    func testDoesNotSynthesizeCalendarOccurrenceDeletedBeyondCacheCap() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstStart = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let deletedOffset = CalendarPin.maximumRecurringOccurrencesPerSeries
        let authoritativeEvents = try (0..<64).compactMap { offset -> CalendarEvent? in
            guard offset != deletedOffset else { return nil }
            let start = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: firstStart))
            return CalendarEvent(
                id: "daily-\(offset)",
                eventIdentifier: "daily-event-\(offset)",
                externalIdentifier: "daily-series",
                title: "毎日の確認 #ピン",
                startDate: start,
                endDate: start.addingTimeInterval(3_600),
                isAllDay: false,
                calendarID: "personal",
                calendarName: "個人",
                calendarColorHex: "21A179",
                location: nil,
                recurrence: CalendarRecurrenceRule(frequency: .daily),
                recurrenceTimeZoneIdentifier: "Asia/Tokyo",
                isRecurring: true,
                canEdit: true
            )
        }
        let validationInterval = DateInterval(
            start: firstStart,
            end: authoritativeEvents.last!.endDate
        )
        let snapshots = CalendarPin.snapshots(
            from: authoritativeEvents,
            at: now,
            recurrenceValidationInterval: validationInterval,
            calendar: calendar
        )
        let deletedStart = try XCTUnwrap(
            calendar.date(byAdding: .day, value: deletedOffset, to: firstStart)
        )
        let expanded = PinnedRecurrenceExpander.expandedPins(
            from: snapshots,
            at: authoritativeEvents[31].endDate.addingTimeInterval(1),
            calendar: calendar
        )

        XCTAssertFalse(
            expanded.contains { $0.startDate == deletedStart },
            "Calendarが削除した例外occurrenceを基礎ルールから復活させない"
        )
    }

    func testDoesNotValidateSeriesWhenLastExpectedOccurrenceIsMissing() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstStart = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let events = try (0..<64).map { offset -> CalendarEvent in
            let start = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: firstStart))
            return recurringCalendarEvent(offset: offset, start: start)
        }
        let missingTailStart = try XCTUnwrap(
            calendar.date(byAdding: .day, value: events.count, to: firstStart)
        )
        let validationInterval = DateInterval(
            start: firstStart,
            end: missingTailStart.addingTimeInterval(1)
        )
        let snapshots = CalendarPin.snapshots(
            from: events,
            at: now,
            recurrenceValidationInterval: validationInterval,
            calendar: calendar
        )

        XCTAssertTrue(snapshots.allSatisfy { $0.recurrenceValidatedThroughDate == nil })
    }

    func testDoesNotSynthesizePastUnpinnedRecurringException() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstStart = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        var events = try (0..<64).map { offset -> CalendarEvent in
            let start = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: firstStart))
            return recurringCalendarEvent(offset: offset, start: start)
        }
        events[CalendarPin.maximumRecurringOccurrencesPerSeries].title = "個別に解除した予定"
        let validationInterval = DateInterval(start: firstStart, end: events.last!.endDate)
        let snapshots = CalendarPin.snapshots(
            from: events,
            at: now,
            recurrenceValidationInterval: validationInterval,
            calendar: calendar
        )

        XCTAssertNil(snapshots.first?.recurrenceValidatedThroughDate)
    }

    func testDoesNotSynthesizePastDetachedRecurringException() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstStart = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        var events = try (0..<64).map { offset -> CalendarEvent in
            let start = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: firstStart))
            return recurringCalendarEvent(offset: offset, start: start)
        }
        events[CalendarPin.maximumRecurringOccurrencesPerSeries].isRecurring = false
        events[CalendarPin.maximumRecurringOccurrencesPerSeries].recurrence = nil
        let validationInterval = DateInterval(start: firstStart, end: events.last!.endDate)
        let snapshots = CalendarPin.snapshots(
            from: events,
            at: now,
            recurrenceValidationInterval: validationInterval,
            calendar: calendar
        )

        XCTAssertTrue(snapshots.allSatisfy { $0.recurrenceValidatedThroughDate == nil })
    }

    func testRecurringExpansionIsIdempotentAndKeepsOnlyThirtyTwoFutureOccurrences() throws {
        let event = recurringEvent(
            start: now.addingTimeInterval(-86_400),
            recurrence: CalendarRecurrenceRule(frequency: .daily)
        )
        var snapshot = event.pinnedSnapshot
        snapshot.recurrenceValidatedThroughDate = now.addingTimeInterval(64 * 86_400)
        let once = PinnedRecurrenceExpander.expandedPins(
            from: [snapshot],
            at: now
        )
        let twice = PinnedRecurrenceExpander.expandedPins(from: once, at: now)

        XCTAssertEqual(once, twice)
        XCTAssertEqual(once.filter { $0.endDate > now }.count, 32)
    }

    func testMonthlyRecurrenceSkipsMonthsWithoutTheAnchoredDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let january = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2033,
            month: 1,
            day: 31,
            hour: 9
        )))
        let event = recurringEvent(
            start: january,
            recurrence: CalendarRecurrenceRule(frequency: .monthly)
        )
        var snapshot = event.pinnedSnapshot
        snapshot.recurrenceValidatedThroughDate = try XCTUnwrap(calendar.date(
            byAdding: .year,
            value: 1,
            to: january
        ))
        let expanded = PinnedRecurrenceExpander.expandedPins(
            from: [snapshot],
            at: january.addingTimeInterval(3_601),
            calendar: calendar,
            futureOccurrenceLimit: 1
        )
        let next = try XCTUnwrap(expanded.first { $0.startDate > january })
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: next.startDate)

        XCTAssertEqual(components.year, 2033)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 31)
        XCTAssertEqual(components.hour, 9)
    }

    func testDailyRecurrenceKeepsEventTimeZoneAcrossDST() throws {
        var eventCalendar = Calendar(identifier: .gregorian)
        eventCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        var deviceCalendar = Calendar(identifier: .gregorian)
        deviceCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let anchor = try XCTUnwrap(eventCalendar.date(from: DateComponents(
            year: 2033,
            month: 3,
            day: 12,
            hour: 9
        )))
        let event = recurringEvent(
            start: anchor,
            recurrence: CalendarRecurrenceRule(frequency: .daily)
        )
        let encoded = try JSONEncoder().encode(event.pinnedSnapshot)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["recurrenceTimeZoneIdentifier"] = "America/Los_Angeles"
        let enriched = try JSONSerialization.data(withJSONObject: object)
        var snapshot = try JSONDecoder().decode(PinnedEvent.self, from: enriched)
        snapshot.recurrenceValidatedThroughDate = try XCTUnwrap(eventCalendar.date(
            byAdding: .day,
            value: 3,
            to: anchor
        ))

        let expanded = PinnedRecurrenceExpander.expandedPins(
            from: [snapshot],
            at: anchor.addingTimeInterval(3_601),
            calendar: deviceCalendar,
            futureOccurrenceLimit: 1
        )
        let next = try XCTUnwrap(expanded.first { $0.startDate > anchor })
        let components = eventCalendar.dateComponents(
            [.year, .month, .day, .hour],
            from: next.startDate
        )

        XCTAssertEqual(components.year, 2033)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 13)
        XCTAssertEqual(components.hour, 9)
    }

    func testLegacyIndefiniteRecurrenceWithoutValidationDoesNotSynthesize() {
        let event = recurringEvent(
            start: now.addingTimeInterval(-86_400),
            recurrence: CalendarRecurrenceRule(frequency: .daily)
        )

        XCTAssertEqual(
            PinnedRecurrenceExpander.expandedPins(from: [event.pinnedSnapshot], at: now),
            [event.pinnedSnapshot]
        )
    }

    func testDoesNotGuessPastOccurrenceCountBoundary() {
        let event = recurringEvent(
            start: now.addingTimeInterval(-86_400),
            recurrence: CalendarRecurrenceRule(frequency: .daily, occurrenceCount: 100)
        )

        XCTAssertEqual(
            PinnedRecurrenceExpander.expandedPins(from: [event.pinnedSnapshot], at: now),
            [event.pinnedSnapshot]
        )
    }

    func testSchedulesBoundariesForPinThatEntersAfterAVisiblePinEnds() {
        let first = pin(id: "first", start: now.addingTimeInterval(-100), end: now.addingTimeInterval(10))
        let longRunning = ["b", "c", "d", "e", "f", "g"].map { id in
            pin(id: id, start: now.addingTimeInterval(-100), end: now.addingTimeInterval(1_000))
        }
        let replacement = pin(
            id: "replacement",
            start: now.addingTimeInterval(20),
            end: now.addingTimeInterval(30)
        )

        let states = WidgetTimelinePlanner.states(
            from: [first] + longRunning + [replacement],
            at: now,
            limit: 7
        )

        XCTAssertEqual(states.map(\.date), [
            now,
            now.addingTimeInterval(12),
            now.addingTimeInterval(22),
            now.addingTimeInterval(32),
            now.addingTimeInterval(1_002)
        ])
        guard states.count == 5 else { return }
        XCTAssertEqual(states[1].pins.map(\.id), ["b", "c", "d", "e", "f", "g", "replacement"])
        XCTAssertEqual(states[2].pins.map(\.id), ["replacement", "b", "c", "d", "e", "f", "g"])
        XCTAssertEqual(states[3].pins.map(\.id), ["b", "c", "d", "e", "f", "g"])
    }

    func testSchedulesStartForOverflowPinThatBecomesOngoingBeforeVisiblePinsEnd() {
        let longRunning = ["b", "c", "d", "e", "f", "g", "h"].map { id in
            pin(id: id, start: now.addingTimeInterval(-100), end: now.addingTimeInterval(1_000))
        }
        let replacement = pin(
            id: "replacement",
            start: now.addingTimeInterval(20),
            end: now.addingTimeInterval(30)
        )

        let states = WidgetTimelinePlanner.states(
            from: longRunning + [replacement],
            at: now,
            limit: 7
        )

        XCTAssertEqual(states.map(\.date), [
            now,
            now.addingTimeInterval(22),
            now.addingTimeInterval(32),
            now.addingTimeInterval(1_002)
        ])
        guard states.count == 4 else { return }
        XCTAssertEqual(states[1].pins.map(\.id), ["replacement", "b", "c", "d", "e", "f", "g"])
        XCTAssertEqual(states[2].pins.map(\.id), ["b", "c", "d", "e", "f", "g", "h"])
    }

    private func pin(id: String, start: Date, end: Date) -> PinnedEvent {
        PinnedEvent(
            id: id,
            eventIdentifier: id,
            externalIdentifier: nil,
            title: id,
            startDate: start,
            endDate: end,
            isAllDay: false,
            calendarName: "Kan",
            calendarColorHex: "5B8DEF",
            location: nil
        )
    }

    private func recurringEvent(
        start: Date,
        recurrence: CalendarRecurrenceRule
    ) -> CalendarEvent {
        CalendarEvent(
            id: "recurring",
            eventIdentifier: "recurring-event",
            externalIdentifier: "recurring-series",
            title: "繰り返し #ピン",
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            isAllDay: false,
            calendarID: "personal",
            calendarName: "個人",
            calendarColorHex: "21A179",
            location: nil,
            recurrence: recurrence,
            isRecurring: true,
            canEdit: true
        )
    }

    private func recurringCalendarEvent(offset: Int, start: Date) -> CalendarEvent {
        CalendarEvent(
            id: "daily-\(offset)",
            eventIdentifier: "daily-event-\(offset)",
            externalIdentifier: "daily-series",
            title: "毎日の確認 #ピン",
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            isAllDay: false,
            calendarID: "personal",
            calendarName: "個人",
            calendarColorHex: "21A179",
            location: nil,
            recurrence: CalendarRecurrenceRule(frequency: .daily),
            recurrenceTimeZoneIdentifier: "Asia/Tokyo",
            isRecurring: true,
            canEdit: true
        )
    }
}
