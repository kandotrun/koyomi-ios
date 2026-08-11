import Foundation
import XCTest
@testable import KoyomiCore

final class UpcomingAgendaBuilderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    func testGroupsActiveAndFutureEventsByDisplayDayInChronologicalOrder() {
        let now = date(2026, 8, 10, 12)
        let ongoingAllDay = event("ongoing", start: date(2026, 8, 10, 0), end: date(2026, 8, 11, 0), allDay: true)
        let laterToday = event("later-today", start: date(2026, 8, 10, 16), end: date(2026, 8, 10, 17))
        let tomorrow = event("tomorrow", start: date(2026, 8, 11, 9), end: date(2026, 8, 11, 10))
        let ended = event("ended", start: date(2026, 8, 10, 8), end: date(2026, 8, 10, 9))

        let sections = UpcomingAgendaBuilder.sections(
            from: [tomorrow, ended, laterToday, ongoingAllDay],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(sections.map(\.day), [date(2026, 8, 10, 0), date(2026, 8, 11, 0)])
        XCTAssertEqual(sections[0].events.map(\.id), ["ongoing", "later-today"])
        XCTAssertEqual(sections[1].events.map(\.id), ["tomorrow"])
    }

    func testOngoingOvernightEventAppearsUnderTodayRatherThanItsPastStartDay() {
        let now = date(2026, 8, 10, 12)
        let overnight = event("overnight", start: date(2026, 8, 9, 23), end: date(2026, 8, 10, 13))

        let sections = UpcomingAgendaBuilder.sections(from: [overnight], now: now, calendar: calendar)

        XCTAssertEqual(sections.map(\.day), [date(2026, 8, 10, 0)])
        XCTAssertEqual(sections[0].events.map(\.id), ["overnight"])
    }

    func testEmptyAndEndedOnlyInputsProduceNoSections() {
        let now = date(2026, 8, 10, 12)
        let ended = event("ended", start: date(2026, 8, 10, 8), end: now)

        XCTAssertEqual(
            UpcomingAgendaBuilder.sections(from: [ended], now: now, calendar: calendar),
            []
        )
    }

    func testOverdueEstimatedTaskStaysUnderTodayUntilCompleted() {
        let now = date(2026, 8, 10, 12)
        var overdue = event(
            "overdue-estimated",
            start: date(2026, 7, 1, 0),
            end: date(2026, 8, 1, 0),
            allDay: true
        )
        overdue.title = "指輪の刻印 #タスク #見込み"
        var completed = overdue
        completed.id = "completed-estimated"
        completed.endDate = date(2026, 9, 2, 0)
        completed.title += " #完了"
        let endedOrdinary = event(
            "ended-ordinary",
            start: date(2026, 7, 1, 0),
            end: date(2026, 8, 1, 0),
            allDay: true
        )

        let sections = UpcomingAgendaBuilder.sections(
            from: [endedOrdinary, completed, overdue],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(sections.map(\.day), [date(2026, 8, 10, 0)])
        XCTAssertEqual(sections[0].events.map(\.id), ["overdue-estimated"])
    }

    private func event(_ id: String, start: Date, end: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(
            id: id,
            eventIdentifier: "event-\(id)",
            externalIdentifier: nil,
            title: id,
            startDate: start,
            endDate: end,
            isAllDay: allDay,
            calendarName: "Kan",
            calendarColorHex: "4F7DF3",
            location: nil
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
