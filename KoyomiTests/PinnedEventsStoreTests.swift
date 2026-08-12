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


    func testMigratesLegacyStorageWhenPrimaryIsEmpty() throws {
        let primary = InMemoryPinnedEventsDataStorage()
        let legacy = InMemoryPinnedEventsDataStorage()
        let event = makeEvent(id: "legacy", start: Date(timeIntervalSince1970: 100))
        try PinnedEventsStore(storage: legacy).save([event])

        let migratingStore = PinnedEventsStore(storage: primary, migrationStorage: legacy)

        XCTAssertEqual(try migratingStore.loadMigrationState(), [event])
        XCTAssertEqual(PinnedEventsStore(storage: primary).load(), [event])
    }

    func testPrimaryStorageWinsOverLegacyStorage() throws {
        let primary = InMemoryPinnedEventsDataStorage()
        let legacy = InMemoryPinnedEventsDataStorage()
        let primaryEvent = makeEvent(id: "primary", start: Date(timeIntervalSince1970: 100))
        let legacyEvent = makeEvent(id: "legacy", start: Date(timeIntervalSince1970: 200))
        try PinnedEventsStore(storage: primary).save([primaryEvent])
        try PinnedEventsStore(storage: legacy).save([legacyEvent])

        let migratingStore = PinnedEventsStore(storage: primary, migrationStorage: legacy)

        XCTAssertEqual(migratingStore.load(), [primaryEvent])
        XCTAssertEqual(PinnedEventsStore(storage: primary).load(), [primaryEvent])
        XCTAssertEqual(PinnedEventsStore(storage: legacy).load(), [primaryEvent])
    }

    func testEmptyPrimaryConsumesStaleLegacyFallback() throws {
        let primary = InMemoryPinnedEventsDataStorage()
        let legacy = InMemoryPinnedEventsDataStorage()
        let stale = makeEvent(id: "stale", start: Date(timeIntervalSince1970: 100))
        try PinnedEventsStore(storage: primary).save([])
        try PinnedEventsStore(storage: legacy).save([stale])
        let migratingStore = PinnedEventsStore(storage: primary, migrationStorage: legacy)

        XCTAssertEqual(try migratingStore.loadMigrationState(), [])
        XCTAssertEqual(PinnedEventsStore(storage: legacy).load(), [])
    }

    func testMigrationStateKeepsLegacyFallbackWhenPrimaryWriteFails() throws {
        let primary = InMemoryPinnedEventsDataStorage()
        let legacy = InMemoryPinnedEventsDataStorage()
        let event = makeEvent(id: "legacy", start: Date(timeIntervalSince1970: 100))
        try PinnedEventsStore(storage: legacy).save([event])
        try PinnedEventsStore(storage: primary).save([event])
        primary.shouldFailWrites = true
        let migratingStore = PinnedEventsStore(storage: primary, migrationStorage: legacy)
        XCTAssertEqual(try migratingStore.loadMigrationState(), [event])

        XCTAssertThrowsError(try migratingStore.saveMigrationState([]))

        XCTAssertEqual(PinnedEventsStore(storage: primary).load(), [event])
        XCTAssertEqual(PinnedEventsStore(storage: legacy).load(), [event])
    }

    func testMigrationStateKeepsPrimaryWhenFallbackWriteFails() throws {
        let primary = InMemoryPinnedEventsDataStorage()
        let legacy = InMemoryPinnedEventsDataStorage()
        let event = makeEvent(id: "legacy", start: Date(timeIntervalSince1970: 100))
        try PinnedEventsStore(storage: primary).save([event])
        try PinnedEventsStore(storage: legacy).save([event])
        legacy.shouldFailWrites = true
        let migratingStore = PinnedEventsStore(storage: primary, migrationStorage: legacy)

        XCTAssertThrowsError(try migratingStore.saveMigrationState([]))

        XCTAssertEqual(PinnedEventsStore(storage: primary).load(), [event])
        XCTAssertEqual(PinnedEventsStore(storage: legacy).load(), [event])
    }

    func testFallbackIsNotReturnedUntilItIsPromotedToPrimary() throws {
        let primary = InMemoryPinnedEventsDataStorage()
        let legacy = InMemoryPinnedEventsDataStorage()
        let event = makeEvent(id: "legacy", start: Date(timeIntervalSince1970: 100))
        try PinnedEventsStore(storage: legacy).save([event])
        primary.shouldFailWrites = true
        let migratingStore = PinnedEventsStore(storage: primary, migrationStorage: legacy)

        XCTAssertThrowsError(try migratingStore.loadMigrationState())
        XCTAssertEqual(PinnedEventsStore(storage: legacy).load(), [event])
    }

    func testPrimaryMigrationStateIsNotReturnedWhenFallbackCannotSynchronize() throws {
        let primary = InMemoryPinnedEventsDataStorage()
        let legacy = InMemoryPinnedEventsDataStorage()
        let event = makeEvent(id: "legacy", start: Date(timeIntervalSince1970: 100))
        try PinnedEventsStore(storage: primary).save([event])
        legacy.shouldFailWrites = true
        let migratingStore = PinnedEventsStore(storage: primary, migrationStorage: legacy)

        XCTAssertThrowsError(try migratingStore.loadMigrationState())
        XCTAssertEqual(PinnedEventsStore(storage: primary).load(), [event])
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

private final class InMemoryPinnedEventsDataStorage: PinnedEventsDataStorage, @unchecked Sendable {
    enum StorageError: Error { case writeFailed }

    private let lock = NSLock()
    private var data: Data?
    var shouldFailWrites = false

    func read() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func write(_ data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        if shouldFailWrites { throw StorageError.writeFailed }
        self.data = data
    }
}
