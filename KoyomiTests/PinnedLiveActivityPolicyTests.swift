import Foundation
import XCTest
@testable import KoyomiCore

final class PinnedLiveActivityPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_786_406_400)

    func testExactTwelveHourBoundaryStartsImmediately() throws {
        let event = pin(
            id: "boundary",
            start: now.addingTimeInterval(12 * 3_600)
        )

        let plan = try XCTUnwrap(
            PinnedLiveActivityPolicy.plans(from: [event], at: now).first
        )

        XCTAssertEqual(plan.event, event)
        XCTAssertEqual(plan.activationDate, now)
        XCTAssertTrue(plan.startsImmediately)
    }

    func testFuturePinIsScheduledForTwelveHoursBeforeItsStart() throws {
        let event = pin(
            id: "future",
            start: now.addingTimeInterval(3 * 86_400 + 900)
        )

        let plan = try XCTUnwrap(
            PinnedLiveActivityPolicy.plans(from: [event], at: now).first
        )

        XCTAssertEqual(
            plan.activationDate,
            event.startDate.addingTimeInterval(-12 * 3_600)
        )
        XCTAssertFalse(plan.startsImmediately)
    }

    func testStartedPinsAndCompletedEstimatedTasksAreExcluded() {
        let exactlyStarting = pin(
            id: "exact-start",
            start: now,
            end: now.addingTimeInterval(3_600)
        )
        let ongoing = pin(
            id: "ongoing",
            start: now.addingTimeInterval(-60),
            end: now.addingTimeInterval(3_600)
        )
        var completedEstimate = pin(
            id: "completed-estimate",
            title: "応募確認 #タスク #見込み #完了",
            start: now.addingTimeInterval(3_600),
            end: now.addingTimeInterval(8 * 86_400),
            isAllDay: true
        )
        completedEstimate.endDate = completedEstimate.startDate.addingTimeInterval(7 * 86_400)

        XCTAssertTrue(
            PinnedLiveActivityPolicy.plans(
                from: [exactlyStarting, ongoing, completedEstimate],
                at: now
            ).isEmpty
        )
    }

    func testAllEligiblePinsAreReturnedInStablePriorityOrder() {
        let pins = (0..<7).reversed().map { index in
            pin(
                id: "event-\(index)",
                start: now.addingTimeInterval(TimeInterval(index + 1) * 3_600)
            )
        }

        XCTAssertEqual(
            PinnedLiveActivityPolicy.plans(from: pins, at: now).map(\.event.id),
            [
                "event-0",
                "event-1",
                "event-2",
                "event-3",
                "event-4",
                "event-5",
                "event-6",
            ]
        )
    }

    func testOversizedEventIdentityIsExcludedFromLiveActivityOnly() {
        let oversizedID = String(
            repeating: "x",
            count: PinnedLiveActivityPolicy.maximumEventIDUTF8Bytes + 1
        )
        let event = pin(
            id: oversizedID,
            start: now.addingTimeInterval(3_600)
        )

        XCTAssertTrue(PinnedLiveActivityPolicy.plans(from: [event], at: now).isEmpty)
    }

    func testLiveActivityTextIsBoundedBelowActivityKitPayloadLimit() throws {
        let hostileChunk = "\u{0}\n\\\"👨‍👩‍👧‍👦予定"
        let longTitle = String(repeating: hostileChunk, count: 1_000) + " #ピン"
        let longCalendarName = String(repeating: "\u{0}\r\\\"🗓️仕事", count: 1_000)
        var event = pin(
            id: String(repeating: "i", count: PinnedLiveActivityPolicy.maximumEventIDUTF8Bytes),
            title: longTitle,
            start: now.addingTimeInterval(3_600)
        )
        event.calendarName = longCalendarName

        let title = PinnedLiveActivityPolicy.displayTitle(for: event)
        let calendarName = PinnedLiveActivityPolicy.calendarName(for: event)
        XCTAssertLessThanOrEqual(
            title.utf8.count,
            PinnedLiveActivityPolicy.maximumTitleUTF8Bytes
        )
        XCTAssertLessThanOrEqual(
            calendarName.utf8.count,
            PinnedLiveActivityPolicy.maximumCalendarNameUTF8Bytes
        )
        XCTAssertFalse(title.contains("#ピン"))
        XCTAssertFalse(title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains))
        XCTAssertFalse(calendarName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains))

        #if canImport(ActivityKit) && os(iOS)
        let attributes = PinnedEventActivityAttributes(
            eventID: event.id,
            scheduledStartDate: event.startDate
        )
        let state = PinnedEventActivityAttributes.ContentState(
            title: title,
            calendarName: calendarName,
            calendarColorHex: event.calendarColorHex,
            startDate: event.startDate,
            isAllDay: event.isAllDay,
            isEstimatedDateWindow: event.isEstimatedDateWindow
        )
        let combinedSize = try JSONEncoder().encode(attributes).count
            + JSONEncoder().encode(state).count
        XCTAssertLessThan(combinedSize, 4_096)
        #endif
    }

    func testAllDayAndOpenEstimatedPinsRemainEligible() {
        let allDay = pin(
            id: "all-day",
            start: now.addingTimeInterval(6 * 3_600),
            end: now.addingTimeInterval(30 * 3_600),
            isAllDay: true
        )
        let estimated = pin(
            id: "estimated",
            title: "受け取り #タスク #見込み",
            start: now.addingTimeInterval(8 * 3_600),
            end: now.addingTimeInterval(8 * 86_400),
            isAllDay: true
        )

        XCTAssertEqual(
            PinnedLiveActivityPolicy.plans(
                from: [estimated, allDay],
                at: now
            ).map(\.event.id),
            ["all-day", "estimated"]
        )
    }

    private func pin(
        id: String,
        title: String? = nil,
        start: Date,
        end: Date? = nil,
        isAllDay: Bool = false
    ) -> PinnedEvent {
        PinnedEvent(
            id: id,
            eventIdentifier: id,
            externalIdentifier: nil,
            title: title ?? id,
            startDate: start,
            endDate: end ?? start.addingTimeInterval(3_600),
            isAllDay: isAllDay,
            calendarName: "仕事",
            calendarColorHex: "5B8DEF",
            location: nil
        )
    }
}
