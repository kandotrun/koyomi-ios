import Foundation
import XCTest
@testable import KoyomiCore

final class WidgetPinSelectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testActiveSelectionPrefersOngoingThenNearestUpcomingAndDropsEnded() {
        let ended = makeEvent(id: "ended", start: -7_200, end: -3_600)
        let later = makeEvent(id: "later", start: 7_200, end: 10_800)
        let ongoing = makeEvent(id: "ongoing", start: -60, end: 1_800)
        let sooner = makeEvent(id: "sooner", start: 3_600, end: 5_400)

        let selected = WidgetPinSelector.activePins(
            from: [later, ended, sooner, ongoing],
            at: now,
            limit: 3
        )

        XCTAssertEqual(selected.map(\.id), ["ongoing", "sooner", "later"])
    }

    func testSelectionHonorsLimitAndAZeroLimitIsEmpty() {
        let first = makeEvent(id: "first", start: 60, end: 120)
        let second = makeEvent(id: "second", start: 180, end: 240)

        XCTAssertEqual(
            WidgetPinSelector.activePins(from: [second, first], at: now, limit: 1).map(\.id),
            ["first"]
        )
        XCTAssertEqual(WidgetPinSelector.activePins(from: [first], at: now, limit: 0), [])
    }

    func testOccurrenceIdentifierIsStableButSeparatesRecurringInstances() {
        let firstStart = now.addingTimeInterval(86_400)
        let secondStart = now.addingTimeInterval(2 * 86_400)

        let firstID = EventOccurrenceID.make(
            eventIdentifier: "recurring-event",
            externalIdentifier: "external",
            startDate: firstStart
        )
        let sameID = EventOccurrenceID.make(
            eventIdentifier: "recurring-event",
            externalIdentifier: "external",
            startDate: firstStart
        )
        let secondID = EventOccurrenceID.make(
            eventIdentifier: "recurring-event",
            externalIdentifier: "external",
            startDate: secondStart
        )

        XCTAssertEqual(firstID, sameID)
        XCTAssertNotEqual(firstID, secondID)
    }

    private func makeEvent(id: String, start: TimeInterval, end: TimeInterval) -> PinnedEvent {
        PinnedEvent(
            id: id,
            eventIdentifier: id,
            externalIdentifier: nil,
            title: id,
            startDate: now.addingTimeInterval(start),
            endDate: now.addingTimeInterval(end),
            isAllDay: false,
            calendarName: "Kan",
            calendarColorHex: "4F7DF3",
            location: nil
        )
    }
}
