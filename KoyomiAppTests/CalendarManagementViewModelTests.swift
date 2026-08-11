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
        let event = makeEvent(title: "請求書を送る #タスク #仕事")
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

    func testDeletingPinnedEventRemovesItFromAgendaAndWidgetSnapshot() throws {
        let event = makeEvent(title: "削除する予定 #仕事")
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
        let event = makeEvent(title: "非表示Calendarの予定 #仕事")
        let fixture = try makeFixture(events: [event], pinned: [event.pinnedSnapshot])
        fixture.model.deselectAllCalendars()
        XCTAssertTrue(fixture.model.events.isEmpty)

        let resolved = fixture.model.event(for: event.pinnedSnapshot)

        XCTAssertEqual(resolved.id, event.id)
        XCTAssertEqual(resolved.calendarID, "work")
        XCTAssertTrue(resolved.canEdit)
    }

    func testPinSyncFailureDoesNotTurnSuccessfulCalendarMutationIntoFailure() throws {
        let event = makeEvent(title: "請求書を送る #タスク")
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
        return Fixture(model: model, source: source, now: now)
    }

    private func makeEvent(
        idSuffix: String = "1",
        title: String
    ) -> CalendarEvent {
        let start = Date(timeIntervalSince1970: 1_786_410_000)
        let eventIdentifier = "event-\(idSuffix)"
        let externalIdentifier = "external-\(idSuffix)"
        return CalendarEvent(
            id: EventOccurrenceID.make(
                eventIdentifier: eventIdentifier,
                externalIdentifier: externalIdentifier,
                startDate: start
            ),
            eventIdentifier: eventIdentifier,
            externalIdentifier: externalIdentifier,
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
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

    init(events: [CalendarEvent]) {
        storedEvents = events
    }

    func requestFullAccess() async throws -> Bool { true }

    func events(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEvent] {
        storedEvents.filter {
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
        throw CalendarEventSourceError.unsupported
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
    let now: Date
}
