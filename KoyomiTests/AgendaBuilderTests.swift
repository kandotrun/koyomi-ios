import Foundation
import XCTest
@testable import KoyomiCore

final class AgendaBuilderTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3_600)!
        return calendar
    }

    func testEventsOnDayIncludeOverlapsAndExcludeTouchingBoundaries() {
        let day = date(2026, 8, 10, 12)
        let allDay = event("all-day", start: date(2026, 8, 10, 0), end: date(2026, 8, 11, 0), allDay: true)
        let timed = event("timed", start: date(2026, 8, 10, 15), end: date(2026, 8, 10, 16))
        let overnight = event("overnight", start: date(2026, 8, 9, 23), end: date(2026, 8, 10, 1))
        let endedAtBoundary = event("ended", start: date(2026, 8, 9, 22), end: date(2026, 8, 10, 0))
        let startsAtNextBoundary = event("tomorrow", start: date(2026, 8, 11, 0), end: date(2026, 8, 11, 1))

        let result = AgendaBuilder.events(
            on: day,
            from: [startsAtNextBoundary, timed, endedAtBoundary, overnight, allDay],
            calendar: calendar
        )

        XCTAssertEqual(result.map(\.id), ["all-day", "overnight", "timed"])
    }

    func testTimedEventsAtSameTimeUseTitleAsStableTieBreaker() {
        let day = date(2026, 8, 10, 12)
        var beta = event("beta", start: date(2026, 8, 10, 9), end: date(2026, 8, 10, 10))
        beta.title = "B"
        var alpha = event("alpha", start: date(2026, 8, 10, 9), end: date(2026, 8, 10, 10))
        alpha.title = "A"

        let result = AgendaBuilder.events(on: day, from: [beta, alpha], calendar: calendar)

        XCTAssertEqual(result.map(\.id), ["alpha", "beta"])
    }

    func testPinSnapshotUsesOccurrenceIdentityAndKeepsOnlyDisplayFields() {
        let source = event(
            "source-id",
            start: date(2026, 8, 10, 9),
            end: date(2026, 8, 10, 10)
        )

        let pin = source.pinnedSnapshot

        XCTAssertFalse(pin.id.isEmpty)
        XCTAssertEqual(pin.eventIdentifier, "event-source-id")
        XCTAssertEqual(pin.externalIdentifier, "external-source-id")
        XCTAssertEqual(pin.title, source.title)
        XCTAssertEqual(pin.startDate, source.startDate)
        XCTAssertEqual(pin.calendarColorHex, source.calendarColorHex)
    }

    private func event(_ id: String, start: Date, end: Date, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(
            id: id,
            eventIdentifier: "event-\(id)",
            externalIdentifier: "external-\(id)",
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
