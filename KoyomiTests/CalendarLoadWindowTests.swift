import Foundation
import XCTest
@testable import KoyomiCore

final class CalendarLoadWindowTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    func testWindowContainsTheEntireSelectedDay() throws {
        let selected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12)))
        let interval = try XCTUnwrap(
            CalendarLoadWindow.interval(
                around: selected,
                calendar: calendar,
                monthsBefore: 1,
                monthsAfter: 18
            )
        )

        XCTAssertTrue(CalendarLoadWindow.contains(day: selected, in: interval, calendar: calendar))
    }

    func testWindowRejectsADayBeyondTheLoadedRange() throws {
        let selected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        let farFuture = try XCTUnwrap(calendar.date(from: DateComponents(year: 2028, month: 3, day: 1)))
        let interval = try XCTUnwrap(CalendarLoadWindow.interval(around: selected, calendar: calendar))

        XCTAssertFalse(CalendarLoadWindow.contains(day: farFuture, in: interval, calendar: calendar))
    }

    func testDayThatStartsAtIntervalEndIsNotContained() throws {
        let selected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        let interval = try XCTUnwrap(CalendarLoadWindow.interval(around: selected, calendar: calendar))

        XCTAssertFalse(CalendarLoadWindow.contains(day: interval.end, in: interval, calendar: calendar))
    }

    func testContainmentUsesCalendarDaysAcrossDST() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let selected = try XCTUnwrap(losAngeles.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        let interval = try XCTUnwrap(CalendarLoadWindow.interval(around: selected, calendar: losAngeles))

        XCTAssertTrue(CalendarLoadWindow.contains(day: selected, in: interval, calendar: losAngeles))
    }
}
