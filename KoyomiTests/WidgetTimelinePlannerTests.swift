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
}
