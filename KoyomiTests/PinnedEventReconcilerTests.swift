import Foundation
import XCTest
@testable import KoyomiCore

final class PinnedEventReconcilerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testExactOccurrenceRefreshesSnapshotAndToleratesDuplicateEventIDs() {
        let pin = makeEvent(id: "same", title: "旧タイトル").pinnedSnapshot
        let first = makeEvent(id: "same", title: "新タイトル")
        let duplicate = makeEvent(id: "same", title: "重複")

        let result = PinnedEventReconciler.reconcile(pins: [pin], with: [first, duplicate])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "新タイトル")
    }

    func testMovedOccurrenceWithSameEventIdentifierIsReconnected() {
        let old = makeEvent(id: "old", title: "発表", start: now)
        let moved = makeEvent(id: "new", title: "発表（変更）", start: now.addingTimeInterval(86_400))

        let result = PinnedEventReconciler.reconcile(pins: [old.pinnedSnapshot], with: [moved])

        XCTAssertEqual(result, [moved.pinnedSnapshot])
    }

    func testOccurrenceMovedBeyondToleranceKeepsOriginalSnapshot() {
        let old = makeEvent(id: "old", title: "発表", start: now)
        let far = makeEvent(id: "far", title: "別の回", start: now.addingTimeInterval(8 * 86_400))

        let result = PinnedEventReconciler.reconcile(pins: [old.pinnedSnapshot], with: [far])

        XCTAssertEqual(result, [old.pinnedSnapshot])
    }

    func testEmptyEventIdentifierDoesNotGuessAMatch() {
        var old = makeEvent(id: "old", title: "発表")
        old.eventIdentifier = ""
        var candidate = makeEvent(id: "new", title: "別予定")
        candidate.eventIdentifier = ""

        let result = PinnedEventReconciler.reconcile(pins: [old.pinnedSnapshot], with: [candidate])

        XCTAssertEqual(result, [old.pinnedSnapshot])
    }

    private func makeEvent(
        id: String,
        title: String,
        start: Date? = nil
    ) -> CalendarEvent {
        let start = start ?? now
        return CalendarEvent(
            id: id,
            eventIdentifier: "event-1",
            externalIdentifier: "external-1",
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            isAllDay: false,
            calendarName: "Kan",
            calendarColorHex: "5B8DEF",
            location: nil
        )
    }
}
