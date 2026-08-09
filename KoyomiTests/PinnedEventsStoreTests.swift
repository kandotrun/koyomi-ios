import Foundation
import XCTest
@testable import KoyomiCore

final class PinnedEventsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "KoyomiCoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testTogglePersistsAndThenRemovesTheSameOccurrence() throws {
        let store = PinnedEventsStore(defaults: defaults, key: "pins")
        let event = makeEvent(id: "dentist@1", start: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(try store.toggle(event), [event])
        XCTAssertTrue(store.contains(id: event.id))

        XCTAssertEqual(try store.toggle(event), [])
        XCTAssertFalse(store.contains(id: event.id))
    }

    func testSaveDeduplicatesByOccurrenceAndSortsChronologically() throws {
        let store = PinnedEventsStore(defaults: defaults, key: "pins")
        let later = makeEvent(id: "later", start: Date(timeIntervalSince1970: 300))
        let earlier = makeEvent(id: "earlier", start: Date(timeIntervalSince1970: 100))
        var updatedEarlier = earlier
        updatedEarlier.title = "更新された予定"

        try store.save([later, earlier, updatedEarlier])

        XCTAssertEqual(store.load().map(\.id), ["earlier", "later"])
        XCTAssertEqual(store.load().first?.title, "更新された予定")
    }

    func testCorruptPayloadFailsClosedToAnEmptyList() {
        defaults.set(Data("not-json".utf8), forKey: "pins")
        let store = PinnedEventsStore(defaults: defaults, key: "pins")

        XCTAssertEqual(store.load(), [])
    }

    private func makeEvent(id: String, start: Date) -> PinnedEvent {
        PinnedEvent(
            id: id,
            eventIdentifier: id,
            externalIdentifier: nil,
            title: "歯科検診",
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            isAllDay: false,
            calendarName: "Personal",
            calendarColorHex: "19A974",
            location: "広島"
        )
    }
}
