import Foundation
import XCTest
@testable import KoyomiCore

final class CountdownCalculatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testUpcomingEventCountsDownToStart() {
        let event = makeEvent(
            start: now.addingTimeInterval(2 * 86_400 + 3 * 3_600 + 4 * 60 + 5),
            end: now.addingTimeInterval(2 * 86_400 + 4 * 3_600)
        )

        let presentation = CountdownCalculator.presentation(for: event, now: now)

        XCTAssertEqual(presentation.phase, .upcoming)
        XCTAssertEqual(presentation.label, "あと")
        XCTAssertEqual(presentation.value, "2日 03:04:05")
        XCTAssertEqual(presentation.targetDate, event.startDate)
    }

    func testOngoingEventCountsDownToEnd() {
        let event = makeEvent(
            start: now.addingTimeInterval(-60),
            end: now.addingTimeInterval(3_600 + 30 * 60 + 5)
        )

        let presentation = CountdownCalculator.presentation(for: event, now: now)

        XCTAssertEqual(presentation.phase, .ongoing)
        XCTAssertEqual(presentation.label, "開催中・終了まで")
        XCTAssertEqual(presentation.value, "01:30:05")
        XCTAssertEqual(presentation.targetDate, event.endDate)
    }

    func testCompactUpcomingTextRoundsAwayDistractingSeconds() {
        let event = makeEvent(
            start: now.addingTimeInterval(11 * 3_600 + 56 * 60 + 38),
            end: now.addingTimeInterval(13 * 3_600)
        )

        XCTAssertEqual(
            CountdownCalculator.compactText(for: event, now: now),
            "あと12時間"
        )
    }

    func testCompactUpcomingTextChoosesADayMinuteOrImminentUnit() {
        XCTAssertEqual(
            CountdownCalculator.compactText(
                for: makeEvent(
                    start: now.addingTimeInterval(2 * 86_400 + 3 * 3_600),
                    end: now.addingTimeInterval(3 * 86_400)
                ),
                now: now
            ),
            "あと2日"
        )
        XCTAssertEqual(
            CountdownCalculator.compactText(
                for: makeEvent(
                    start: now.addingTimeInterval(36 * 60 + 1),
                    end: now.addingTimeInterval(3_600)
                ),
                now: now
            ),
            "あと37分"
        )
        XCTAssertEqual(
            CountdownCalculator.compactText(
                for: makeEvent(
                    start: now.addingTimeInterval(30),
                    end: now.addingTimeInterval(60)
                ),
                now: now
            ),
            "まもなく"
        )
    }

    func testCompactTextKeepsOngoingAndEndedMeaning() {
        XCTAssertEqual(
            CountdownCalculator.compactText(
                for: makeEvent(
                    start: now.addingTimeInterval(-60),
                    end: now.addingTimeInterval(3_600 + 30 * 60)
                ),
                now: now
            ),
            "終了まで2時間"
        )
        XCTAssertEqual(
            CountdownCalculator.compactText(
                for: makeEvent(
                    start: now.addingTimeInterval(-7_200),
                    end: now.addingTimeInterval(-1)
                ),
                now: now
            ),
            "終了"
        )
    }

    func testCompactEstimatedTextKeepsWindowMeaning() {
        var upcoming = makeEvent(
            start: now.addingTimeInterval(14 * 86_400),
            end: now.addingTimeInterval(43 * 86_400)
        )
        upcoming.title = "指輪の刻印 #タスク #見込み"
        upcoming.isAllDay = true
        var ongoing = upcoming
        ongoing.startDate = now.addingTimeInterval(-14 * 86_400)
        ongoing.endDate = now.addingTimeInterval(15 * 86_400)
        var overdue = upcoming
        overdue.startDate = now.addingTimeInterval(-31 * 86_400)
        overdue.endDate = now.addingTimeInterval(-2 * 86_400)

        XCTAssertEqual(CountdownCalculator.compactText(for: upcoming, now: now), "見込みまで14日")
        XCTAssertEqual(CountdownCalculator.compactText(for: ongoing, now: now), "遅くとも14日")
        XCTAssertEqual(CountdownCalculator.compactText(for: overdue, now: now), "3日超過")
    }

    func testEndedEventDoesNotShowADecreasingTimer() {
        let event = makeEvent(
            start: now.addingTimeInterval(-7_200),
            end: now.addingTimeInterval(-1)
        )

        let presentation = CountdownCalculator.presentation(for: event, now: now)

        XCTAssertEqual(presentation.phase, .ended)
        XCTAssertEqual(presentation.label, "終了")
        XCTAssertEqual(presentation.value, "終了")
        XCTAssertNil(presentation.targetDate)
    }

    func testStartAndEndBoundariesAreUnambiguous() {
        let event = makeEvent(start: now, end: now.addingTimeInterval(60))
        XCTAssertEqual(CountdownCalculator.presentation(for: event, now: now).phase, .ongoing)
        XCTAssertEqual(
            CountdownCalculator.presentation(for: event, now: event.endDate).phase,
            .ended
        )
    }

    func testEstimatedWindowUsesDayLevelCopyBeforeDuringAndAfterTheWindow() {
        var upcoming = makeEvent(
            start: now.addingTimeInterval(14 * 86_400),
            end: now.addingTimeInterval(43 * 86_400)
        )
        upcoming.title = "指輪の刻印 #タスク #見込み"
        upcoming.isAllDay = true
        var ongoing = upcoming
        ongoing.startDate = now.addingTimeInterval(-14 * 86_400)
        ongoing.endDate = now.addingTimeInterval(15 * 86_400)
        var overdue = upcoming
        overdue.startDate = now.addingTimeInterval(-31 * 86_400)
        overdue.endDate = now.addingTimeInterval(-2 * 86_400)

        let before = CountdownCalculator.presentation(for: upcoming, now: now)
        let inside = CountdownCalculator.presentation(for: ongoing, now: now)
        let late = CountdownCalculator.presentation(for: overdue, now: now)
        var completed = upcoming
        completed.title += " #完了"
        let done = CountdownCalculator.presentation(for: completed, now: now)

        XCTAssertEqual(before.label, "見込み期間まで")
        XCTAssertEqual(before.value, "14日")
        XCTAssertEqual(inside.label, "見込み期間内・遅くとも")
        XCTAssertEqual(inside.value, "14日")
        XCTAssertEqual(late.phase, .overdue)
        XCTAssertEqual(late.label, "要確認・超過")
        XCTAssertEqual(late.value, "3日")
        XCTAssertEqual(done.phase, .ended)
        XCTAssertEqual(done.label, "完了")
        XCTAssertEqual(done.value, "完了")
        XCTAssertNil(done.targetDate)
    }

    func testDeadlineProximityUsesFiveStableRemainingTimeBands() {
        let cases: [(remaining: TimeInterval, level: Int, label: String)] = [
            (31 * 86_400, 1, "余裕あり"),
            (30 * 86_400, 2, "近づいています"),
            (7 * 86_400, 3, "近い"),
            (24 * 3_600, 4, "かなり近い"),
            (3_600, 5, "まもなく")
        ]

        for item in cases {
            let event = makeEvent(
                start: now.addingTimeInterval(item.remaining),
                end: now.addingTimeInterval(item.remaining + 3_600)
            )

            let proximity = CountdownProximityCalculator.state(for: event, now: now)

            XCTAssertEqual(proximity.level, item.level)
            XCTAssertEqual(proximity.totalSegmentCount, 5)
            XCTAssertEqual(proximity.label, item.label)
            XCTAssertEqual(proximity.activeSegmentIndex, item.level - 1)
        }
    }

    func testDeadlineProximityCountsOngoingEventsTowardTheirEnd() {
        let event = makeEvent(
            start: now.addingTimeInterval(-86_400),
            end: now.addingTimeInterval(30 * 60)
        )

        let proximity = CountdownProximityCalculator.state(for: event, now: now)

        XCTAssertEqual(proximity.level, 5)
        XCTAssertEqual(proximity.label, "まもなく")
    }

    func testDeadlineProximityMarksOverdueEstimatedWindowForReview() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let window = try XCTUnwrap(CalendarEstimatedWindow.centered(
            on: now.addingTimeInterval(-20 * 86_400),
            bufferDays: 14,
            calendar: calendar
        ))
        var event = makeEvent(start: window.startDate, end: window.endDate)
        event.title = "受け取り #タスク #見込み"
        event.isAllDay = true

        let proximity = CountdownProximityCalculator.state(
            for: event,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(proximity.level, 5)
        XCTAssertEqual(proximity.label, "要確認")
        XCTAssertEqual(proximity.accessibilityDescription, "期限の近さ、要確認、5段階中5")
    }

    func testDeadlineProximityKeepsEstimatedWindowMeaningWhileInsideIt() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let window = try XCTUnwrap(CalendarEstimatedWindow.centered(
            on: now.addingTimeInterval(7 * 86_400),
            bufferDays: 14,
            calendar: calendar
        ))
        var event = makeEvent(start: window.startDate, end: window.endDate)
        event.title = "受け取り #タスク #見込み"
        event.isAllDay = true

        let proximity = CountdownProximityCalculator.state(
            for: event,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(proximity.level, 4)
        XCTAssertEqual(proximity.label, "見込み期間内")
    }

    func testDeadlineProximityShowsNoActiveSegmentsAfterAnExactEventEnds() {
        let event = makeEvent(
            start: now.addingTimeInterval(-7_200),
            end: now.addingTimeInterval(-1)
        )

        let proximity = CountdownProximityCalculator.state(for: event, now: now)

        XCTAssertEqual(proximity.level, 0)
        XCTAssertNil(proximity.activeSegmentIndex)
        XCTAssertEqual(proximity.totalSegmentCount, 5)
        XCTAssertEqual(proximity.label, "終了")
    }

    private func makeEvent(start: Date, end: Date) -> PinnedEvent {
        PinnedEvent(
            id: "event@\(start.timeIntervalSince1970)",
            eventIdentifier: "event",
            externalIdentifier: "external-event",
            title: "プロジェクト発表",
            startDate: start,
            endDate: end,
            isAllDay: false,
            calendarName: "Kan",
            calendarColorHex: "4F7DF3",
            location: nil
        )
    }
}
