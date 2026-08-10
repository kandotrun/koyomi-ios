import Foundation
import XCTest
@testable import KoyomiCore

final class CalendarSelectionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CalendarSelectionStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFirstLaunchSelectsEveryAvailableCalendar() {
        let store = CalendarSelectionStore(defaults: defaults, key: "selection")

        XCTAssertEqual(
            store.loadSelection(availableCalendars: calendars),
            Set(["personal", "work"])
        )
    }

    func testExplicitEmptySelectionRemainsEmpty() throws {
        let store = CalendarSelectionStore(defaults: defaults, key: "selection")
        try store.saveSelection([])

        XCTAssertEqual(store.loadSelection(availableCalendars: calendars), [])
    }

    func testSavedSelectionDropsCalendarsThatNoLongerExist() throws {
        let store = CalendarSelectionStore(defaults: defaults, key: "selection")
        try store.saveSelection(["personal", "removed"])

        XCTAssertEqual(
            store.loadSelection(availableCalendars: calendars),
            Set(["personal"])
        )
    }

    func testNewCalendarIsNotSilentlyEnabledAfterUserMakesAChoice() throws {
        let store = CalendarSelectionStore(defaults: defaults, key: "selection")
        try store.saveSelection(["personal"])
        let expanded = calendars + [
            CalendarDescriptor(id: "birthdays", title: "誕生日", sourceName: "iCloud", colorHex: "F59E0B")
        ]

        XCTAssertEqual(
            store.loadSelection(availableCalendars: expanded),
            Set(["personal"])
        )
    }

    private var calendars: [CalendarDescriptor] {
        [
            CalendarDescriptor(id: "personal", title: "個人", sourceName: "iCloud", colorHex: "19A974"),
            CalendarDescriptor(id: "work", title: "仕事", sourceName: "Google", colorHex: "4F7DF3")
        ]
    }
}
