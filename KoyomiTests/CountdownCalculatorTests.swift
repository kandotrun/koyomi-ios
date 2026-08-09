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
