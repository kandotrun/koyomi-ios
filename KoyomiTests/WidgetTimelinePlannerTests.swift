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
}
