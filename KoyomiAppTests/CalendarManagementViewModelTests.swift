import Foundation
import XCTest
@testable import Koyomi

@MainActor
final class CalendarManagementViewModelTests: XCTestCase {
    func testAccessibilityDynamicTypeUsesVerticalCardLayout() {
        XCTAssertFalse(KoyomiResponsiveLayout.usesVerticalCardLayout(for: .large))
        XCTAssertTrue(KoyomiResponsiveLayout.usesVerticalCardLayout(for: .accessibility1))
        XCTAssertTrue(KoyomiResponsiveLayout.usesVerticalCardLayout(for: .accessibility5))
    }

    func testPinnedSectionTimelineSwitchesAtTheNextLifecycleBoundary() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let ongoing = pinnedEvent(
            id: "ongoing",
            start: now.addingTimeInterval(-60),
            end: now.addingTimeInterval(10)
        )
        let upcoming = pinnedEvent(
            id: "upcoming",
            start: now.addingTimeInterval(20),
            end: now.addingTimeInterval(80)
        )
        let pins = [ongoing, upcoming]

        XCTAssertEqual(KoyomiPinnedTimeline.nextBoundary(in: pins, after: now), ongoing.endDate)
        XCTAssertEqual(KoyomiPinnedTimeline.visiblePins(from: pins, at: now).first?.id, ongoing.id)
        XCTAssertEqual(
            KoyomiPinnedTimeline.visiblePins(
                from: pins,
                at: ongoing.endDate.addingTimeInterval(0.001)
            ).first?.id,
            upcoming.id
        )
    }

    func testCreatesTaskAndRefreshesAgenda() throws {
        let fixture = try makeFixture(events: [])
        let start = fixture.now.addingTimeInterval(3_600)
        let draft = CalendarItemDraft(
            kind: .task,
            readableTitle: "請求書を送る",
            startDate: start,
            endDate: start.addingTimeInterval(1_800),
            isAllDay: false,
            calendarID: "work",
            tags: ["仕事"],
            isImportant: true
        )

        let created = fixture.model.createItem(draft)

        XCTAssertEqual(created?.managementKind, .task)
        XCTAssertEqual(created?.titleMetadata.tags, ["タスク", "重要", "仕事"])
        XCTAssertTrue(fixture.model.events.contains(where: { $0.id == created?.id }))
        XCTAssertNil(fixture.model.errorMessage)
    }

    func testCreatingEstimatedTaskPinsItAutomatically() throws {
        let fixture = try makeFixture(events: [])
        let center = fixture.now.addingTimeInterval(30 * 86_400)
        let window = try XCTUnwrap(
            CalendarEstimatedWindow.centered(on: center, bufferDays: 14)
        )
        let draft = CalendarItemDraft(
            kind: .task,
            dateMode: .estimatedWindow,
            readableTitle: "指輪の刻印が完了",
            startDate: window.startDate,
            endDate: window.endDate,
            isAllDay: true,
            calendarID: "work",
            isImportant: true
        )

        let created = try XCTUnwrap(fixture.model.createItem(draft))

        XCTAssertTrue(fixture.model.isPinned(created))
        XCTAssertEqual(fixture.model.pinnedEvents.map(\.id), [created.pinnedSnapshot.id])
    }

    func testCalendarTitleIsTheSourceOfTruthForPins() throws {
        let calendarPinned = makeEvent(
            idSuffix: "calendar-pin",
            title: "Calendarで固定した予定 #仕事 #ピン"
        )
        let staleStoredPin = makeEvent(
            idSuffix: "stale-cache",
            title: "古い端末内キャッシュ #仕事"
        )

        let fixture = try makeFixture(
            events: [calendarPinned, staleStoredPin],
            pinned: [staleStoredPin.pinnedSnapshot]
        )

        XCTAssertTrue(fixture.model.isPinned(calendarPinned))
        XCTAssertFalse(fixture.model.isPinned(staleStoredPin))
        XCTAssertEqual(fixture.model.pinnedEvents.map(\.id), [calendarPinned.pinnedSnapshot.id])
    }

    func testRefreshReflectsExternalCalendarPinTagChanges() throws {
        let event = makeEvent(title: "外部で編集する予定 #仕事")
        let fixture = try makeFixture(events: [event])
        XCTAssertTrue(fixture.model.pinnedEvents.isEmpty)

        fixture.source.storedEvents[0].title = EventTitleTagMutator.applying(
            EventTitleTagChange(adding: [CalendarPin.tag], removing: []),
            to: fixture.source.storedEvents[0].title
        )
        fixture.model.refresh()
        XCTAssertEqual(fixture.model.pinnedEvents.map(\.id), [event.pinnedSnapshot.id])

        fixture.source.storedEvents[0].title = EventTitleTagMutator.applying(
            EventTitleTagChange(adding: [], removing: [CalendarPin.tag]),
            to: fixture.source.storedEvents[0].title
        )
        fixture.model.refresh()
        XCTAssertTrue(fixture.model.pinnedEvents.isEmpty)
        XCTAssertTrue(fixture.pinStore.load().isEmpty)
    }

    func testLegacyStoredPinMigratesToCalendarTitleAndIsThenCleared() throws {
        let event = makeEvent(title: "旧バージョンで固定した予定 #仕事")
        let suite = "CalendarManagementViewModelTests.pinMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshotStore = PinnedEventsStore(defaults: defaults, key: "snapshots-v2")
        let legacyPrimaryStorage = UserDefaultsPinnedEventsDataStorage(
            defaults: defaults,
            key: "pins-v1-primary"
        )
        let legacyFallbackStorage = UserDefaultsPinnedEventsDataStorage(
            defaults: defaults,
            key: "pins-v1-fallback"
        )
        let legacyStore = PinnedEventsStore(
            storage: legacyPrimaryStorage,
            migrationStorage: legacyFallbackStorage
        )
        let legacyFallbackStore = PinnedEventsStore(storage: legacyFallbackStorage)
        try legacyFallbackStore.save([event.pinnedSnapshot])
        let source = ManagementFakeSource(events: [event])
        let model = CalendarViewModel(
            source: source,
            pinStore: snapshotStore,
            legacyPinStore: legacyStore,
            calendarSelectionStore: CalendarSelectionStore(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_786_406_400) }
        )

        model.bootstrap()

        let migrated = try XCTUnwrap(source.storedEvents.first)
        XCTAssertTrue(migrated.titleMetadata.containsTag("ピン"))
        XCTAssertTrue(model.isPinned(migrated))
        XCTAssertEqual(model.pinnedEvents.map(\.id), [migrated.pinnedSnapshot.id])
        XCTAssertTrue(legacyStore.load().isEmpty)
        XCTAssertTrue(legacyFallbackStore.load().isEmpty)
    }

    func testLegacyPinOutsideDiscoveryWindowSeedsTheDerivedSnapshotCache() throws {
        let now = Date(timeIntervalSince1970: 1_786_406_400)
        let farStart = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(byAdding: .year, value: 6, to: now)
        )
        let event = makeEvent(
            idSuffix: "far-legacy",
            title: "遠い将来の旧ピン",
            startDate: farStart,
            endDate: farStart.addingTimeInterval(3_600)
        )
        let suite = "CalendarManagementViewModelTests.farLegacyPin.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshotStore = PinnedEventsStore(defaults: defaults, key: "snapshots-v2")
        let legacyStore = PinnedEventsStore(defaults: defaults, key: "pins-v1")
        try legacyStore.save([event.pinnedSnapshot])
        let source = ManagementFakeSource(events: [event])
        let model = CalendarViewModel(
            source: source,
            pinStore: snapshotStore,
            legacyPinStore: legacyStore,
            calendarSelectionStore: CalendarSelectionStore(defaults: defaults),
            now: { now }
        )

        model.bootstrap()

        let migrated = try XCTUnwrap(source.storedEvents.first)
        XCTAssertTrue(migrated.isPinned)
        XCTAssertEqual(model.pinnedEvents.map(\.id), [migrated.pinnedSnapshot.id])
        XCTAssertEqual(snapshotStore.load().map(\.id), [migrated.pinnedSnapshot.id])
    }

    func testLegacyPinUsesExternalIdentifierWhenEventKitIdentifierRotates() throws {
        let legacy = makeEvent(idSuffix: "rotated", title: "ID変更前の予定")
        var current = legacy
        current.eventIdentifier = "event-rotated-new"
        current.id = EventOccurrenceID.make(
            eventIdentifier: current.eventIdentifier,
            externalIdentifier: current.externalIdentifier,
            startDate: current.startDate
        )
        let suite = "CalendarManagementViewModelTests.externalIdentity.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacyStore = PinnedEventsStore(defaults: defaults, key: "pins-v1")
        try legacyStore.save([legacy.pinnedSnapshot])
        let source = ManagementFakeSource(events: [current])
        let model = CalendarViewModel(
            source: source,
            pinStore: PinnedEventsStore(defaults: defaults, key: "snapshots-v2"),
            legacyPinStore: legacyStore,
            calendarSelectionStore: CalendarSelectionStore(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_786_406_400) }
        )

        model.bootstrap()

        let migrated = try XCTUnwrap(source.storedEvents.first)
        XCTAssertTrue(migrated.isPinned)
        XCTAssertEqual(model.pinnedEvents.map(\.id), [migrated.pinnedSnapshot.id])
    }

    func testLegacyMigrationDoesNotTouchCalendarUntilLegacyStateIsConsumed() throws {
        let event = makeEvent(title: "移行前の予定 #仕事")
        let legacyStorage = SwitchablePinnedStorage()
        let legacyStore = PinnedEventsStore(storage: legacyStorage)
        try legacyStore.save([event.pinnedSnapshot])
        legacyStorage.shouldFailWrites = true

        let suite = "CalendarManagementViewModelTests.pinMigrationWriteFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = ManagementFakeSource(events: [event])
        let model = CalendarViewModel(
            source: source,
            pinStore: PinnedEventsStore(defaults: defaults, key: "snapshots-v2"),
            legacyPinStore: legacyStore,
            calendarSelectionStore: CalendarSelectionStore(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_786_406_400) }
        )

        model.bootstrap()

        XCTAssertFalse(try XCTUnwrap(source.storedEvents.first).isPinned)
        XCTAssertEqual(legacyStore.load(), [event.pinnedSnapshot])
        XCTAssertTrue(model.errorMessage?.contains("移行できませんでした") == true)
    }

    func testLegacyMigrationKeepsPinForRetryWhenCalendarMutationFails() throws {
        let event = makeEvent(title: "一時的に移行できない予定 #仕事")
        let suite = "CalendarManagementViewModelTests.pinMigrationMutationFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacyStore = PinnedEventsStore(defaults: defaults, key: "pins-v1")
        try legacyStore.save([event.pinnedSnapshot])
        let source = ManagementFakeSource(events: [event])
        source.shouldFailPinMutations = true
        let model = CalendarViewModel(
            source: source,
            pinStore: PinnedEventsStore(defaults: defaults, key: "snapshots-v2"),
            legacyPinStore: legacyStore,
            calendarSelectionStore: CalendarSelectionStore(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_786_406_400) }
        )

        model.bootstrap()

        XCTAssertFalse(try XCTUnwrap(source.storedEvents.first).isPinned)
        XCTAssertEqual(legacyStore.load(), [event.pinnedSnapshot])
        XCTAssertTrue(model.errorMessage?.contains("移行できませんでした") == true)
    }

    func testLegacyMigrationDoesNotRestorePinWhenCalendarMutationCommittedBeforeThrowing() throws {
        let event = makeEvent(title: "保存後に応答を失う予定 #仕事")
        let suite = "CalendarManagementViewModelTests.pinMigrationCommittedFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacyStore = PinnedEventsStore(defaults: defaults, key: "pins-v1")
        try legacyStore.save([event.pinnedSnapshot])
        let source = ManagementFakeSource(events: [event])
        source.shouldFailPinMutationsAfterWrite = true
        let model = CalendarViewModel(
            source: source,
            pinStore: PinnedEventsStore(defaults: defaults, key: "snapshots-v2"),
            legacyPinStore: legacyStore,
            calendarSelectionStore: CalendarSelectionStore(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_786_406_400) }
        )

        model.bootstrap()

        XCTAssertTrue(try XCTUnwrap(source.storedEvents.first).isPinned)
        XCTAssertTrue(legacyStore.load().isEmpty)
        XCTAssertEqual(model.pinnedEvents.count, 1)
        XCTAssertNil(model.errorMessage)
    }

    func testLegacyPinReconnectsToAnOccurrenceMovedWithinSevenDays() throws {
        let original = makeEvent(idSuffix: "moved", title: "移動前の予定 #仕事")
        var moved = original
        moved.startDate = original.startDate.addingTimeInterval(86_400)
        moved.endDate = original.endDate.addingTimeInterval(86_400)
        moved.id = EventOccurrenceID.make(
            eventIdentifier: moved.eventIdentifier,
            externalIdentifier: moved.externalIdentifier,
            startDate: moved.startDate
        )
        let suite = "CalendarManagementViewModelTests.movedPinMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshotStore = PinnedEventsStore(defaults: defaults, key: "snapshots-v2")
        let legacyStore = PinnedEventsStore(defaults: defaults, key: "pins-v1")
        try legacyStore.save([original.pinnedSnapshot])
        let source = ManagementFakeSource(events: [moved])
        let model = CalendarViewModel(
            source: source,
            pinStore: snapshotStore,
            legacyPinStore: legacyStore,
            calendarSelectionStore: CalendarSelectionStore(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_786_406_400) }
        )

        model.bootstrap()

        let migrated = try XCTUnwrap(source.storedEvents.first)
        XCTAssertTrue(migrated.isPinned)
        XCTAssertTrue(legacyStore.load().isEmpty)
        XCTAssertEqual(model.pinnedEvents.map(\.id), [migrated.pinnedSnapshot.id])
    }

    func testAmbiguousMovedLegacyPinFailsClosedAndRemainsForRetry() throws {
        let original = makeEvent(idSuffix: "ambiguous", title: "移動前の予定 #仕事")
        var earlier = original
        earlier.startDate = original.startDate.addingTimeInterval(-86_400)
        earlier.endDate = original.endDate.addingTimeInterval(-86_400)
        earlier.id = EventOccurrenceID.make(
            eventIdentifier: earlier.eventIdentifier,
            externalIdentifier: earlier.externalIdentifier,
            startDate: earlier.startDate
        )
        var later = original
        later.startDate = original.startDate.addingTimeInterval(86_400)
        later.endDate = original.endDate.addingTimeInterval(86_400)
        later.id = EventOccurrenceID.make(
            eventIdentifier: later.eventIdentifier,
            externalIdentifier: later.externalIdentifier,
            startDate: later.startDate
        )
        let suite = "CalendarManagementViewModelTests.ambiguousPinMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacyStore = PinnedEventsStore(defaults: defaults, key: "pins-v1")
        try legacyStore.save([original.pinnedSnapshot])
        let source = ManagementFakeSource(events: [earlier, later])
        let model = CalendarViewModel(
            source: source,
            pinStore: PinnedEventsStore(defaults: defaults, key: "snapshots-v2"),
            legacyPinStore: legacyStore,
            calendarSelectionStore: CalendarSelectionStore(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_786_406_400) }
        )

        model.bootstrap()

        XCTAssertTrue(source.storedEvents.allSatisfy { !$0.isPinned })
        XCTAssertEqual(legacyStore.load(), [original.pinnedSnapshot])
        XCTAssertTrue(model.errorMessage?.contains("移行できませんでした") == true)
    }

    func testDeletedRecurringLegacyOccurrenceDoesNotPinItsNeighbor() throws {
        let original = makeEvent(idSuffix: "deleted-recurring", title: "削除済み定例 #仕事")
        var nextOccurrence = original
        nextOccurrence.startDate = original.startDate.addingTimeInterval(7 * 86_400)
        nextOccurrence.endDate = original.endDate.addingTimeInterval(7 * 86_400)
        nextOccurrence.id = EventOccurrenceID.make(
            eventIdentifier: nextOccurrence.eventIdentifier,
            externalIdentifier: nextOccurrence.externalIdentifier,
            startDate: nextOccurrence.startDate
        )
        nextOccurrence.isRecurring = true
        let suite = "CalendarManagementViewModelTests.deletedRecurringPinMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacyStore = PinnedEventsStore(defaults: defaults, key: "pins-v1")
        try legacyStore.save([original.pinnedSnapshot])
        let source = ManagementFakeSource(events: [nextOccurrence])
        let model = CalendarViewModel(
            source: source,
            pinStore: PinnedEventsStore(defaults: defaults, key: "snapshots-v2"),
            legacyPinStore: legacyStore,
            calendarSelectionStore: CalendarSelectionStore(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_786_406_400) }
        )

        model.bootstrap()

        XCTAssertTrue(source.storedEvents.allSatisfy { !$0.isPinned })
        XCTAssertTrue(legacyStore.load().isEmpty)
    }

    func testPinnedEventOutsideDiscoveryWindowIsRevalidatedFromCalendar() throws {
        let farStart = try XCTUnwrap(Calendar(identifier: .gregorian).date(
            byAdding: .year,
            value: 6,
            to: Date(timeIntervalSince1970: 1_786_406_400)
        ))
        let event = makeEvent(
            idSuffix: "far-pin",
            title: "遠い将来の予定 #ピン",
            startDate: farStart,
            endDate: farStart.addingTimeInterval(3_600)
        )
        let fixture = try makeFixture(events: [event], pinned: [event.pinnedSnapshot])

        XCTAssertEqual(fixture.model.pinnedEvents.map(\.id), [event.pinnedSnapshot.id])
    }

    func testRetryableOutOfWindowPinRevalidationKeepsItsCacheCandidate() throws {
        let farStart = try XCTUnwrap(Calendar(identifier: .gregorian).date(
            byAdding: .year,
            value: 6,
            to: Date(timeIntervalSince1970: 1_786_406_400)
        ))
        let event = makeEvent(
            idSuffix: "far-retry",
            title: "再照合を待つ遠い予定 #ピン",
            startDate: farStart,
            endDate: farStart.addingTimeInterval(3_600)
        )
        let fixture = try makeFixture(events: [event], pinned: [event.pinnedSnapshot])
        fixture.source.failEventReadsShorterThan = 7_200

        fixture.model.refresh()

        XCTAssertEqual(fixture.model.pinnedEvents.map(\.id), [event.pinnedSnapshot.id])
        XCTAssertEqual(fixture.pinStore.load().map(\.id), [event.pinnedSnapshot.id])
    }

    func testPinnedEventOutsideDiscoveryWindowSurvivesCalendarDateMove() throws {
        let farStart = try XCTUnwrap(Calendar(identifier: .gregorian).date(
            byAdding: .year,
            value: 6,
            to: Date(timeIntervalSince1970: 1_786_406_400)
        ))
        let original = makeEvent(
            idSuffix: "far-moved",
            title: "遠い将来の予定 #ピン",
            startDate: farStart,
            endDate: farStart.addingTimeInterval(3_600)
        )
        var moved = original
        moved.startDate = original.startDate.addingTimeInterval(86_400)
        moved.endDate = original.endDate.addingTimeInterval(86_400)
        moved.id = EventOccurrenceID.make(
            eventIdentifier: moved.eventIdentifier,
            externalIdentifier: moved.externalIdentifier,
            startDate: moved.startDate
        )
        let fixture = try makeFixture(events: [moved], pinned: [original.pinnedSnapshot])

        XCTAssertEqual(fixture.model.pinnedEvents.map(\.id), [moved.pinnedSnapshot.id])
    }

    func testCachedEventOutsideDiscoveryWindowDoesNotOverrideExternalUnpin() throws {
        let farStart = try XCTUnwrap(Calendar(identifier: .gregorian).date(
            byAdding: .year,
            value: 6,
            to: Date(timeIntervalSince1970: 1_786_406_400)
        ))
        let currentEvent = makeEvent(
            idSuffix: "far-unpinned",
            title: "遠い将来の予定",
            startDate: farStart,
            endDate: farStart.addingTimeInterval(3_600)
        )
        var staleSnapshot = currentEvent.pinnedSnapshot
        staleSnapshot.title = "遠い将来の予定 #ピン"
        let fixture = try makeFixture(events: [currentEvent], pinned: [staleSnapshot])

        XCTAssertTrue(fixture.model.pinnedEvents.isEmpty)
        XCTAssertTrue(fixture.pinStore.load().isEmpty)
    }

    func testTogglePinWritesPinTagToCalendarEvent() throws {
        let event = makeEvent(title: "Calendarへ書き戻す予定 #仕事")
        let fixture = try makeFixture(events: [event])

        let updated = try XCTUnwrap(fixture.model.togglePin(event, scope: .thisEvent))

        let stored = try XCTUnwrap(fixture.source.storedEvents.first)
        XCTAssertEqual(updated, stored)
        XCTAssertTrue(updated.isPinned)
        XCTAssertTrue(fixture.model.isPinned(stored))
        XCTAssertEqual(fixture.model.pinnedEvents.map(\.id), [stored.pinnedSnapshot.id])
    }

    func testRemovePinRemovesOnlyPinTagFromCalendarEvent() throws {
        let event = makeEvent(title: "解除する予定 #ピン #仕事")
        let fixture = try makeFixture(events: [event], pinned: [event.pinnedSnapshot])

        fixture.model.removePin(event.pinnedSnapshot, scope: .thisEvent)

        let stored = try XCTUnwrap(fixture.source.storedEvents.first)
        XCTAssertFalse(stored.titleMetadata.containsTag("ピン"))
        XCTAssertTrue(stored.titleMetadata.containsTag("仕事"))
        XCTAssertFalse(fixture.model.isPinned(stored))
        XCTAssertTrue(fixture.model.pinnedEvents.isEmpty)
    }

    func testRecurringPinToggleForwardsFutureScopeToCalendarSource() throws {
        var event = makeEvent(title: "繰り返しをピン留め")
        event.recurrence = CalendarRecurrenceRule(frequency: .daily)
        event.isRecurring = true
        let fixture = try makeFixture(events: [event])

        XCTAssertNotNil(fixture.model.togglePin(event, scope: .futureEvents))

        XCTAssertEqual(fixture.source.lastPinMutationScope, .futureEvents)
    }

    func testRecurringPinRemovalForwardsFutureScopeToCalendarSource() throws {
        var event = makeEvent(title: "繰り返しを解除 #ピン")
        event.recurrence = CalendarRecurrenceRule(frequency: .daily)
        event.isRecurring = true
        let fixture = try makeFixture(events: [event], pinned: [event.pinnedSnapshot])

        fixture.model.removePin(event.pinnedSnapshot, scope: .futureEvents)

        XCTAssertEqual(fixture.source.lastPinMutationScope, .futureEvents)
    }

    func testAutoPinFailureDoesNotTurnEstimatedCreationIntoFailure() throws {
        let storage = SwitchablePinnedStorage()
        storage.shouldFailWrites = true
        let pinStore = PinnedEventsStore(storage: storage)
        let suite = "CalendarManagementViewModelTests.autoPinFailure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let source = ManagementFakeSource(events: [])
        let now = Date(timeIntervalSince1970: 1_786_406_400)
        let model = CalendarViewModel(
            source: source,
            pinStore: pinStore,
            calendarSelectionStore: CalendarSelectionStore(defaults: defaults),
            now: { now }
        )
        model.bootstrap()
        let window = try XCTUnwrap(
            CalendarEstimatedWindow.centered(
                on: now.addingTimeInterval(30 * 86_400),
                bufferDays: 14
            )
        )
        let draft = CalendarItemDraft(
            kind: .task,
            dateMode: .estimatedWindow,
            readableTitle: "海外加工の完了",
            startDate: window.startDate,
            endDate: window.endDate,
            isAllDay: true,
            calendarID: "work"
        )

        let created = model.createItem(draft)

        XCTAssertNotNil(created)
        XCTAssertEqual(source.storedEvents.count, 1)
        XCTAssertTrue(model.errorMessage?.contains("保存しましたが") == true)
    }

    func testCompletingTaskRefreshesPinnedSnapshotWhenIdentifiersChange() throws {
        let event = makeEvent(title: "請求書を送る #タスク #仕事 #ピン")
        let fixture = try makeFixture(events: [event], pinned: [event.pinnedSnapshot])
        fixture.source.changeIdentifiersOnCompletion = true

        let updated = fixture.model.setTaskCompleted(
            event,
            completed: true,
            scope: .thisEvent
        )

        XCTAssertNotNil(updated)
        XCTAssertTrue(updated?.isCompletedTask == true)
        XCTAssertEqual(fixture.model.pinnedEvents.count, 1)
        XCTAssertTrue(fixture.model.pinnedEvents[0].titleMetadata.containsTag("完了"))
        XCTAssertEqual(fixture.model.pinnedEvents[0].id, updated?.pinnedSnapshot.id)
        XCTAssertNil(fixture.model.errorMessage)
    }

    func testMovingPinnedEventOutsideDiscoveryWindowSeedsUpdatedSnapshot() throws {
        let event = makeEvent(title: "遠い未来へ移す予定 #仕事 #ピン")
        let fixture = try makeFixture(events: [event], pinned: [event.pinnedSnapshot])
        let farStart = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(byAdding: .year, value: 6, to: fixture.now)
        )
        var draft = CalendarItemDraft(event)
        draft.startDate = farStart
        draft.endDate = farStart.addingTimeInterval(3_600)

        let updated = try XCTUnwrap(
            fixture.model.updateItem(event, with: draft, scope: .thisEvent)
        )

        XCTAssertTrue(updated.isPinned)
        XCTAssertEqual(updated.startDate, farStart)
        XCTAssertEqual(fixture.model.pinnedEvents.map(\.id), [updated.pinnedSnapshot.id])
        XCTAssertEqual(fixture.pinStore.load().map(\.id), [updated.pinnedSnapshot.id])
        XCTAssertNil(fixture.model.errorMessage)
    }

    func testDeletingPinnedEventRemovesItFromAgendaAndWidgetSnapshot() throws {
        let event = makeEvent(title: "削除する予定 #仕事 #ピン")
        let fixture = try makeFixture(events: [event], pinned: [event.pinnedSnapshot])

        let deleted = fixture.model.deleteItem(event, scope: .thisEvent)

        XCTAssertTrue(deleted)
        XCTAssertTrue(fixture.model.events.isEmpty)
        XCTAssertTrue(fixture.model.pinnedEvents.isEmpty)
        XCTAssertNil(fixture.model.errorMessage)
    }

    func testSuccessfulCreationRevealsTheNewItem() throws {
        let fixture = try makeFixture(events: [makeEvent(title: "既存予定 #仕事")])
        fixture.model.searchText = "一致しない検索"
        fixture.model.selectItemFilter(.events)

        let start = fixture.now.addingTimeInterval(172_800)
        let draft = CalendarItemDraft(
            kind: .task,
            readableTitle: "表示される新規タスク",
            startDate: start,
            endDate: start.addingTimeInterval(1_800),
            isAllDay: false,
            calendarID: "work"
        )

        let created = try XCTUnwrap(fixture.model.createItem(draft))

        XCTAssertEqual(fixture.model.searchText, "")
        XCTAssertEqual(fixture.model.itemFilter, .all)
        XCTAssertTrue(Calendar.current.isDate(fixture.model.selectedDate, inSameDayAs: start))
        XCTAssertTrue(fixture.model.agendaEvents.contains(created))
    }

    func testOverdueEstimatedTaskStaysInUpcomingUntilCompleted() throws {
        let now = Date(timeIntervalSince1970: 1_786_406_400)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var overdue = makeEvent(title: "指輪の刻印 #タスク #見込み")
        overdue.startDate = try XCTUnwrap(calendar.date(byAdding: .month, value: -3, to: now))
        overdue.endDate = try XCTUnwrap(calendar.date(byAdding: .month, value: -2, to: now))
        overdue.isAllDay = true
        overdue.id = EventOccurrenceID.make(
            eventIdentifier: overdue.eventIdentifier,
            externalIdentifier: overdue.externalIdentifier,
            startDate: overdue.startDate
        )
        let fixture = try makeFixture(events: [overdue])

        XCTAssertTrue(
            fixture.model.upcomingSections
                .flatMap(\.events)
                .contains(where: { $0.id == overdue.id })
        )
    }

    func testPinnedEventFromHiddenCalendarResolvesBeforeOpeningDetail() throws {
        let event = makeEvent(title: "非表示Calendarの予定 #仕事 #ピン")
        let fixture = try makeFixture(events: [event], pinned: [event.pinnedSnapshot])
        fixture.model.deselectAllCalendars()
        XCTAssertTrue(fixture.model.events.isEmpty)
        XCTAssertEqual(fixture.model.pinnedEvents.map(\.id), [event.pinnedSnapshot.id])

        let resolved = fixture.model.event(for: event.pinnedSnapshot)

        XCTAssertEqual(resolved.id, event.id)
        XCTAssertEqual(resolved.calendarID, "work")
        XCTAssertTrue(resolved.canEdit)
    }

    func testColdWidgetDeepLinkWaitsForAuthoritativeBootstrap() throws {
        let event = makeEvent(idSuffix: "cold-link", title: "Widgetから開く予定 #ピン")
        let suite = "CalendarManagementViewModelTests.coldWidgetLink.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let pinStore = PinnedEventsStore(defaults: defaults, key: "snapshots-v2")
        try pinStore.save([event.pinnedSnapshot])
        let model = CalendarViewModel(
            source: ManagementFakeSource(events: [event]),
            pinStore: pinStore,
            calendarSelectionStore: CalendarSelectionStore(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_786_406_400) }
        )
        let encodedID = try XCTUnwrap(
            event.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        )
        let url = try XCTUnwrap(URL(string: "koyomi://event/\(encodedID)"))

        model.open(url)
        XCTAssertNil(model.selectedEvent)

        model.bootstrap()

        XCTAssertEqual(model.selectedEvent?.id, event.id)
        XCTAssertTrue(model.selectedEvent?.isPinned == true)
    }

    func testColdWidgetDeepLinkSurvivesEventKitIdentifierRotation() throws {
        let cached = makeEvent(idSuffix: "cold-rotated", title: "ID変更前の予定 #ピン")
        var current = cached
        current.eventIdentifier = "event-cold-rotated-new"
        current.id = EventOccurrenceID.make(
            eventIdentifier: current.eventIdentifier,
            externalIdentifier: current.externalIdentifier,
            startDate: current.startDate
        )
        let suite = "CalendarManagementViewModelTests.coldRotatedWidgetLink.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let pinStore = PinnedEventsStore(defaults: defaults, key: "snapshots-v2")
        try pinStore.save([cached.pinnedSnapshot])
        let model = CalendarViewModel(
            source: ManagementFakeSource(events: [current]),
            pinStore: pinStore,
            calendarSelectionStore: CalendarSelectionStore(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_786_406_400) }
        )
        let encodedID = try XCTUnwrap(
            cached.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        )
        let url = try XCTUnwrap(URL(string: "koyomi://event/\(encodedID)"))

        model.open(url)
        model.bootstrap()

        XCTAssertEqual(model.selectedEvent?.id, current.id)
        XCTAssertTrue(model.selectedEvent?.isPinned == true)
    }

    func testColdWidgetDeepLinkResolvesSynthesizedRecurringOccurrenceAfterIdentifierRotation() throws {
        let now = Date(timeIntervalSince1970: 1_786_406_400)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = try XCTUnwrap(calendar.date(byAdding: .day, value: -40, to: now))
        let cachedEvent = CalendarEvent(
            id: EventOccurrenceID.make(
                eventIdentifier: "old-recurring-event",
                externalIdentifier: "stable-recurring-series",
                startDate: anchor
            ),
            eventIdentifier: "old-recurring-event",
            externalIdentifier: "stable-recurring-series",
            title: "毎日の確認 #ピン",
            startDate: anchor,
            endDate: anchor.addingTimeInterval(3_600),
            isAllDay: false,
            calendarID: "work",
            calendarName: "仕事",
            calendarColorHex: "5B8DEF",
            location: nil,
            recurrence: CalendarRecurrenceRule(frequency: .daily),
            isRecurring: true,
            canEdit: true
        )
        var cachedPin = cachedEvent.pinnedSnapshot
        cachedPin.recurrenceValidatedThroughDate = try XCTUnwrap(calendar.date(
            byAdding: .day,
            value: 100,
            to: anchor
        ))
        let synthesized = try XCTUnwrap(
            PinnedRecurrenceExpander.expandedPins(
                from: [cachedPin],
                at: now,
                calendar: calendar
            ).first { $0.startDate > now }
        )
        let current = CalendarEvent(
            id: EventOccurrenceID.make(
                eventIdentifier: "new-recurring-event",
                externalIdentifier: cachedEvent.externalIdentifier,
                startDate: synthesized.startDate
            ),
            eventIdentifier: "new-recurring-event",
            externalIdentifier: cachedEvent.externalIdentifier,
            title: cachedEvent.title,
            startDate: synthesized.startDate,
            endDate: synthesized.endDate,
            isAllDay: false,
            calendarID: "work",
            calendarName: "仕事",
            calendarColorHex: "5B8DEF",
            location: nil,
            recurrence: cachedEvent.recurrence,
            isRecurring: true,
            canEdit: true
        )
        let suite = "CalendarManagementViewModelTests.synthesizedColdLink.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let pinStore = PinnedEventsStore(defaults: defaults, key: "snapshots-v2")
        try pinStore.save([cachedPin])
        let model = CalendarViewModel(
            source: ManagementFakeSource(events: [current]),
            pinStore: pinStore,
            calendarSelectionStore: CalendarSelectionStore(defaults: defaults),
            calendar: calendar,
            now: { now }
        )
        let encodedID = try XCTUnwrap(
            synthesized.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        )
        let url = try XCTUnwrap(URL(string: "koyomi://event/\(encodedID)"))

        model.open(url)
        model.bootstrap()

        XCTAssertEqual(model.selectedEvent?.id, current.id)
        XCTAssertTrue(model.selectedEvent?.isPinned == true)
    }

    func testMissingColdWidgetDeepLinkIsDiscardedAfterAuthoritativeBootstrap() throws {
        let event = makeEvent(idSuffix: "late-link", title: "後から現れる予定 #ピン")
        let suite = "CalendarManagementViewModelTests.missingColdWidgetLink.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = ManagementFakeSource(events: [])
        let model = CalendarViewModel(
            source: source,
            pinStore: PinnedEventsStore(defaults: defaults, key: "snapshots-v2"),
            calendarSelectionStore: CalendarSelectionStore(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_786_406_400) }
        )
        let encodedID = try XCTUnwrap(
            event.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        )
        let url = try XCTUnwrap(URL(string: "koyomi://event/\(encodedID)"))

        model.open(url)
        model.bootstrap()
        XCTAssertNil(model.selectedEvent)

        source.storedEvents = [event]
        model.refresh()

        XCTAssertNil(model.selectedEvent)
    }

    func testPinSyncFailureDoesNotTurnSuccessfulCalendarMutationIntoFailure() throws {
        let event = makeEvent(title: "請求書を送る #タスク #ピン")
        let storage = SwitchablePinnedStorage()
        let pinStore = PinnedEventsStore(storage: storage)
        try pinStore.save([event.pinnedSnapshot])
        storage.shouldFailWrites = true

        let suite = "CalendarManagementViewModelTests.failure.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let source = ManagementFakeSource(events: [event])
        source.changeIdentifiersOnCompletion = true
        let model = CalendarViewModel(
            source: source,
            pinStore: pinStore,
            calendarSelectionStore: CalendarSelectionStore(defaults: defaults),
            now: { Date(timeIntervalSince1970: 1_786_406_400) }
        )
        model.bootstrap()

        let updated = model.setTaskCompleted(event, completed: true, scope: .thisEvent)

        XCTAssertNotNil(updated)
        XCTAssertTrue(updated?.isCompletedTask == true)
        XCTAssertTrue(model.errorMessage?.contains("更新しましたが") == true)
    }

    private func pinnedEvent(id: String, start: Date, end: Date) -> PinnedEvent {
        PinnedEvent(
            id: id,
            eventIdentifier: id,
            externalIdentifier: nil,
            title: id,
            startDate: start,
            endDate: end,
            isAllDay: false,
            calendarName: "仕事",
            calendarColorHex: "007AFF",
            location: nil
        )
    }

    private func makeFixture(
        events: [CalendarEvent],
        pinned: [PinnedEvent] = []
    ) throws -> Fixture {
        let suite = "CalendarManagementViewModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let pinStore = PinnedEventsStore(defaults: defaults)
        try pinStore.save(pinned)
        let source = ManagementFakeSource(events: events)
        let now = Date(timeIntervalSince1970: 1_786_406_400)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let model = CalendarViewModel(
            source: source,
            pinStore: pinStore,
            calendarSelectionStore: CalendarSelectionStore(defaults: defaults),
            calendar: calendar,
            now: { now }
        )
        model.bootstrap()
        return Fixture(model: model, source: source, pinStore: pinStore, now: now)
    }

    private func makeEvent(
        idSuffix: String = "1",
        title: String,
        startDate: Date = Date(timeIntervalSince1970: 1_786_410_000),
        endDate: Date? = nil
    ) -> CalendarEvent {
        let eventIdentifier = "event-\(idSuffix)"
        let externalIdentifier = "external-\(idSuffix)"
        return CalendarEvent(
            id: EventOccurrenceID.make(
                eventIdentifier: eventIdentifier,
                externalIdentifier: externalIdentifier,
                startDate: startDate
            ),
            eventIdentifier: eventIdentifier,
            externalIdentifier: externalIdentifier,
            title: title,
            startDate: startDate,
            endDate: endDate ?? startDate.addingTimeInterval(3_600),
            isAllDay: false,
            calendarID: "work",
            calendarName: "仕事",
            calendarColorHex: "5B8DEF",
            location: nil,
            canEdit: true
        )
    }
}

@MainActor
private final class ManagementFakeSource: CalendarEventSource {
    var authorizationStatus: CalendarAccessStatus = .fullAccess
    var availableCalendars: [CalendarDescriptor] = [
        CalendarDescriptor(
            id: "work",
            title: "仕事",
            sourceName: "Google",
            colorHex: "5B8DEF",
            allowsContentModifications: true
        )
    ]
    var storedEvents: [CalendarEvent]
    var changeIdentifiersOnCompletion = false
    var lastPinMutationScope: CalendarMutationScope?
    var failEventReadsShorterThan: TimeInterval?
    var shouldFailPinMutations = false
    var shouldFailPinMutationsAfterWrite = false

    init(events: [CalendarEvent]) {
        storedEvents = events
    }

    func requestFullAccess() async throws -> Bool { true }

    func events(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEvent] {
        if let failEventReadsShorterThan,
           interval.duration < failEventReadsShorterThan {
            throw CalendarEventSourceError.unsupported
        }
        return storedEvents.filter {
            calendarIDs.contains($0.calendarID)
                && $0.endDate > interval.start
                && $0.startDate < interval.end
        }
    }

    func createItem(_ draft: CalendarItemDraft) throws -> CalendarEvent {
        let eventIdentifier = "created-\(storedEvents.count + 1)"
        let title = ManagedCalendarTitle.make(
            readableTitle: draft.readableTitle,
            kind: draft.kind,
            dateMode: draft.dateMode,
            isImportant: draft.isImportant,
            isCompleted: false,
            tags: draft.tags
        )
        let event = CalendarEvent(
            id: EventOccurrenceID.make(
                eventIdentifier: eventIdentifier,
                externalIdentifier: nil,
                startDate: draft.startDate
            ),
            eventIdentifier: eventIdentifier,
            externalIdentifier: nil,
            title: title,
            startDate: draft.startDate,
            endDate: draft.endDate,
            isAllDay: draft.isAllDay,
            calendarID: draft.calendarID,
            calendarName: "仕事",
            calendarColorHex: "5B8DEF",
            location: draft.location,
            notes: draft.notes,
            alarmOffsets: draft.alarmOffsets,
            recurrence: draft.recurrence,
            isRecurring: draft.recurrence != nil,
            canEdit: true
        )
        storedEvents.append(event)
        return event
    }

    func updateItem(
        _ event: CalendarEvent,
        with draft: CalendarItemDraft,
        scope: CalendarMutationScope
    ) throws -> CalendarEvent {
        guard let index = storedEvents.firstIndex(where: { $0.id == event.id }) else {
            throw CalendarEventSourceError.notFound
        }
        var updated = storedEvents[index]
        updated.title = ManagedCalendarTitle.make(
            readableTitle: draft.readableTitle,
            kind: draft.kind,
            dateMode: draft.dateMode,
            isImportant: draft.isImportant,
            isCompleted: draft.isCompleted,
            tags: draft.tags
        )
        updated.startDate = draft.startDate
        updated.endDate = draft.endDate
        updated.isAllDay = draft.isAllDay
        updated.calendarID = draft.calendarID
        updated.location = draft.location
        updated.notes = draft.notes
        updated.alarmOffsets = draft.alarmOffsets
        updated.recurrence = draft.recurrence
        updated.isRecurring = draft.recurrence != nil
        updated.id = EventOccurrenceID.make(
            eventIdentifier: updated.eventIdentifier,
            externalIdentifier: updated.externalIdentifier,
            startDate: updated.startDate
        )
        storedEvents[index] = updated
        return updated
    }

    func setTaskCompletion(
        _ event: CalendarEvent,
        completed: Bool,
        scope: CalendarMutationScope
    ) throws -> CalendarEvent {
        guard let index = storedEvents.firstIndex(where: { $0.id == event.id }) else {
            throw CalendarEventSourceError.notFound
        }
        var updated = storedEvents[index]
        updated.title = EventTitleTagMutator.applying(
            EventTitleTagChange(
                adding: completed ? ["完了"] : [],
                removing: completed ? [] : ["完了"]
            ),
            to: updated.title
        )
        if changeIdentifiersOnCompletion {
            updated.eventIdentifier += "-changed"
            updated.externalIdentifier = "changed-external"
            updated.id = EventOccurrenceID.make(
                eventIdentifier: updated.eventIdentifier,
                externalIdentifier: updated.externalIdentifier,
                startDate: updated.startDate
            )
        }
        storedEvents[index] = updated
        return updated
    }

    func setPinned(
        _ event: CalendarEvent,
        pinned: Bool,
        scope: CalendarMutationScope
    ) throws -> CalendarEvent {
        lastPinMutationScope = scope
        if shouldFailPinMutations {
            throw CalendarEventSourceError.unsupported
        }
        guard let index = storedEvents.firstIndex(where: { $0.id == event.id }) else {
            throw CalendarEventSourceError.notFound
        }
        var updated = storedEvents[index]
        updated.title = EventTitleTagMutator.applying(
            EventTitleTagChange(
                adding: pinned ? [CalendarPin.tag] : [],
                removing: pinned ? [] : [CalendarPin.tag]
            ),
            to: updated.title
        )
        storedEvents[index] = updated
        if shouldFailPinMutationsAfterWrite {
            throw CalendarEventSourceError.unsupported
        }
        return updated
    }

    func deleteItem(_ event: CalendarEvent, scope: CalendarMutationScope) throws {
        guard let index = storedEvents.firstIndex(where: { $0.id == event.id }) else {
            throw CalendarEventSourceError.notFound
        }
        storedEvents.remove(at: index)
    }
}

private final class SwitchablePinnedStorage: PinnedEventsDataStorage, @unchecked Sendable {
    enum StorageError: Error { case writeFailed }

    private let lock = NSLock()
    private var data: Data?
    var shouldFailWrites = false

    func read() throws -> Data? {
        lock.withLock { data }
    }

    func write(_ data: Data) throws {
        try lock.withLock {
            if shouldFailWrites { throw StorageError.writeFailed }
            self.data = data
        }
    }
}

@MainActor
private struct Fixture {
    let model: CalendarViewModel
    let source: ManagementFakeSource
    let pinStore: PinnedEventsStore
    let now: Date
}
