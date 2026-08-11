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

    func testActivePinCountIncludesOverflowPinsAndDropsEndedPins() {
        let ended = makeEvent(id: "ended", start: -120, end: -60)
        let active = (0..<8).map { index in
            makeEvent(
                id: "active-\(index)",
                start: TimeInterval(index * 60),
                end: TimeInterval((index + 10) * 60)
            )
        }

        XCTAssertEqual(
            WidgetPinSelector.activePinCount(from: [ended] + active, at: now),
            8
        )
    }

    func testOverdueEstimatedTaskRemainsVisibleUntilCompleted() {
        var overdue = makeEvent(id: "estimated", start: -30 * 86_400, end: -3 * 86_400)
        overdue.title = "指輪の刻印 #タスク #見込み"
        overdue.isAllDay = true
        var completed = overdue
        completed.id = "completed"
        completed.endDate = now.addingTimeInterval(11 * 86_400)
        completed.title = "完了済み #タスク #見込み #完了"

        XCTAssertEqual(
            WidgetPinSelector.activePins(from: [completed, overdue], at: now, limit: 3).map(\.id),
            ["estimated"]
        )
        XCTAssertEqual(WidgetPinSelector.activePinCount(from: [completed, overdue], at: now), 1)
    }

    func testWidgetLayoutCapacityShowsMorePinsInTheLargeFamily() {
        XCTAssertEqual(WidgetPinLayoutCapacity.single, 1)
        XCTAssertEqual(WidgetPinLayoutCapacity.medium, 3)
        XCTAssertEqual(WidgetPinLayoutCapacity.large, 7)
        XCTAssertEqual(WidgetPinLayoutCapacity.mediumVisibleLimits(isAccessibilitySize: false), [3])
        XCTAssertEqual(WidgetPinLayoutCapacity.mediumVisibleLimits(isAccessibilitySize: true), [3, 2, 1])
        XCTAssertEqual(WidgetPinLayoutCapacity.largeVisibleLimits(isAccessibilitySize: false), [7, 6, 5])
        XCTAssertEqual(WidgetPinLayoutCapacity.largeVisibleLimits(isAccessibilitySize: true), [4, 3, 2, 1])
        XCTAssertEqual(WidgetPinLayoutCapacity.hiddenCount(totalPins: 7, visibleLimit: 6), 1)
        XCTAssertEqual(WidgetPinLayoutCapacity.hiddenCount(totalPins: 7, visibleLimit: 7), 0)
        XCTAssertEqual(WidgetPinLayoutCapacity.hiddenCount(totalPins: 2, visibleLimit: 4), 0)
        XCTAssertEqual(WidgetPinLayoutCapacity.titleLineLimit(isAccessibilitySize: false), 1)
        XCTAssertEqual(WidgetPinLayoutCapacity.titleLineLimit(isAccessibilitySize: true), 3)
    }

    func testAccessibilityCountdownColumnExpandsWithoutTakingTheWholeRow() {
        XCTAssertEqual(
            WidgetPinLayoutCapacity.countdownColumnWidth(isAccessibilitySize: false),
            86
        )
        XCTAssertEqual(
            WidgetPinLayoutCapacity.countdownColumnWidth(isAccessibilitySize: true),
            132
        )
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
