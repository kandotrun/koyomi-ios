import Combine
import Foundation
import WidgetKit

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published private(set) var authorizationStatus: CalendarAccessStatus
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var upcomingEvents: [CalendarEvent] = []
    @Published private(set) var calendars: [CalendarDescriptor] = []
    @Published private(set) var selectedCalendarIDs: Set<String> = []
    @Published private(set) var selectedTag: String?
    @Published var searchText = ""
    @Published private(set) var itemFilter: CalendarItemFilter = .all
    @Published private(set) var pinnedEvents: [PinnedEvent]
    @Published private(set) var isLoading = false
    @Published var selectedDate: Date
    @Published var selectedEvent: CalendarEvent?
    @Published var errorMessage: String?

    private let source: CalendarEventSource
    private let pinStore: PinnedEventsStore
    private let legacyPinStore: PinnedEventsStore?
    private let calendarSelectionStore: CalendarSelectionStore
    private let calendar: Calendar
    private let now: () -> Date
    private let cachedDeepLinkPinsByID: [String: PinnedEvent]
    private var loadedInterval: DateInterval?
    private var pendingDeepLinkedEventID: String?
    private var pendingDeepLinkedPin: PinnedEvent?
    private var editablePinIDs: Set<String> = []

    init(
        source: CalendarEventSource,
        pinStore: PinnedEventsStore,
        legacyPinStore: PinnedEventsStore? = nil,
        calendarSelectionStore: CalendarSelectionStore,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.pinStore = pinStore
        self.legacyPinStore = legacyPinStore
        self.calendarSelectionStore = calendarSelectionStore
        self.calendar = calendar
        self.now = now
        let cachedPins = PinnedRecurrenceExpander.expandedPins(
            from: pinStore.load(),
            at: now(),
            calendar: calendar
        )
        cachedDeepLinkPinsByID = cachedPins.reduce(into: [:]) { result, pin in
            result[pin.id] = pin
        }
        authorizationStatus = source.authorizationStatus
        pinnedEvents = []
        selectedDate = calendar.startOfDay(for: now())
    }

    var agendaEvents: [CalendarEvent] {
        let tagged = EventTagIndex.events(
            from: AgendaBuilder.events(on: selectedDate, from: events, calendar: calendar),
            matching: selectedTag
        )
        return CalendarItemQuery.events(
            from: tagged,
            searchText: searchText,
            filter: itemFilter
        )
    }

    var upcomingSections: [UpcomingAgendaSection] {
        let tagged = EventTagIndex.events(from: upcomingEvents, matching: selectedTag)
        return UpcomingAgendaBuilder.sections(
            from: CalendarItemQuery.events(
                from: tagged,
                searchText: searchText,
                filter: itemFilter
            ),
            now: now(),
            calendar: calendar
        )
    }

    var availableTags: [String] {
        EventTagIndex.tags(in: upcomingEvents + events)
    }

    var displayedPins: [PinnedEvent] {
        let active = WidgetPinSelector.activePins(from: pinnedEvents, at: now(), limit: pinnedEvents.count)
        let activeIDs = Set(active.map(\.id))
        let ended = pinnedEvents
            .filter { !activeIDs.contains($0.id) }
            .sorted { $0.endDate > $1.endDate }
        return active + ended
    }

    var dateChoices: [Date] {
        (-3...3).compactMap { calendar.date(byAdding: .day, value: $0, to: selectedDate) }
    }

    var selectedDateTitle: String {
        if calendar.isDateInToday(selectedDate) { return "今日" }
        if calendar.isDateInTomorrow(selectedDate) { return "明日" }
        if calendar.isDateInYesterday(selectedDate) { return "昨日" }
        return selectedDate.formatted(
            .dateTime.month(.wide).day().weekday(.wide).locale(Locale(identifier: "ja_JP"))
        )
    }

    var isCalendarFilterActive: Bool {
        !calendars.isEmpty && selectedCalendarIDs.count != calendars.count
    }

    func isCalendarSelected(_ calendarID: String) -> Bool {
        selectedCalendarIDs.contains(calendarID)
    }

    func bootstrap() {
        authorizationStatus = source.authorizationStatus
        WidgetCenter.shared.reloadTimelines(ofKind: "KoyomiPinnedCountdown")
        if authorizationStatus == .fullAccess {
            refresh()
        }
    }

    func requestCalendarAccess() async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await source.requestFullAccess()
            authorizationStatus = source.authorizationStatus
            if authorizationStatus == .fullAccess {
                refreshAvailableCalendars()
                let migration = migrateLegacyPins()
                reloadAllEventWindows(additionalPinCandidates: migration.pinCandidates)
                if !migration.succeeded, errorMessage == nil {
                    errorMessage = "以前のピンの一部をCalendarへ移行できませんでした。"
                }
            }
        } catch {
            errorMessage = "カレンダーへのアクセスを確認できませんでした。"
            authorizationStatus = source.authorizationStatus
        }
    }

    func refresh() {
        authorizationStatus = source.authorizationStatus
        guard authorizationStatus == .fullAccess else { return }
        isLoading = true
        defer { isLoading = false }
        refreshAvailableCalendars()
        let migration = migrateLegacyPins()
        reloadAllEventWindows(additionalPinCandidates: migration.pinCandidates)
        if !migration.succeeded, errorMessage == nil {
            errorMessage = "以前のピンの一部をCalendarへ移行できませんでした。"
        }
    }

    func selectDate(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)
        guard authorizationStatus == .fullAccess else { return }
        let isLoaded = loadedInterval.map {
            CalendarLoadWindow.contains(day: selectedDate, in: $0, calendar: calendar)
        } ?? false
        if !isLoaded {
            loadSelectedEventWindow()
        }
    }

    func selectToday() {
        selectDate(now())
    }

    func selectTag(_ tag: String?) {
        selectedTag = EventTagIndex.resolvedSelection(tag, availableTags: availableTags)
    }

    func selectItemFilter(_ filter: CalendarItemFilter) {
        itemFilter = filter
    }

    func toggleCalendar(_ calendarID: String) {
        guard calendars.contains(where: { $0.id == calendarID }) else { return }
        var updated = selectedCalendarIDs
        if !updated.insert(calendarID).inserted {
            updated.remove(calendarID)
        }
        saveCalendarSelection(updated)
    }

    func selectAllCalendars() {
        saveCalendarSelection(Set(calendars.map(\.id)))
    }

    func deselectAllCalendars() {
        saveCalendarSelection([])
    }

    func isPinned(_ event: CalendarEvent) -> Bool {
        event.isPinned
    }

    func isPinEditable(_ pin: PinnedEvent) -> Bool {
        editablePinIDs.contains(pin.id)
    }

    @discardableResult
    func togglePin(
        _ event: CalendarEvent,
        scope: CalendarMutationScope
    ) -> CalendarEvent? {
        let updated: CalendarEvent
        do {
            updated = try source.setPinned(event, pinned: !event.isPinned, scope: scope)
        } catch {
            errorMessage = managementErrorMessage(for: error, action: "変更")
            return nil
        }

        applyLocalReplacement(of: event, with: updated)
        errorMessage = nil
        do {
            try reloadAllEventWindowsOrThrow(additionalPinCandidates: [updated])
        } catch {
            errorMessage = "ピン留めはCalendarへ保存しましたが、一覧またはWidgetの同期を完了できませんでした。"
        }
        return updated
    }

    func removePin(_ pin: PinnedEvent, scope: CalendarMutationScope) {
        let event = event(for: pin)
        guard event.canEdit else {
            errorMessage = "対象の予定をCalendarから再取得できませんでした。"
            return
        }
        let updated: CalendarEvent
        do {
            updated = try source.setPinned(event, pinned: false, scope: scope)
        } catch {
            errorMessage = managementErrorMessage(for: error, action: "変更")
            return
        }

        applyLocalReplacement(of: event, with: updated)
        errorMessage = nil
        do {
            try reloadAllEventWindowsOrThrow(additionalPinCandidates: [updated])
        } catch {
            errorMessage = "ピン留めはCalendarから解除しましたが、一覧またはWidgetの同期を完了できませんでした。"
        }
    }

    @discardableResult
    func createItem(_ draft: CalendarItemDraft) -> CalendarEvent? {
        do {
            var created = try source.createItem(draft)
            applyLocalCreation(created)
            var postSaveIssue = false
            errorMessage = nil
            if draft.dateMode == .estimatedWindow, !isPinned(created) {
                do {
                    let pinned = try source.setPinned(created, pinned: true, scope: .thisEvent)
                    applyLocalReplacement(of: created, with: pinned)
                    created = pinned
                } catch {
                    postSaveIssue = true
                }
            }
            do {
                try ensureCalendarVisible(created.calendarID)
                try reloadAllEventWindowsOrThrow(additionalPinCandidates: [created])
            } catch {
                postSaveIssue = true
            }
            if postSaveIssue {
                errorMessage = draft.dateMode == .estimatedWindow
                    ? "見込みタスクは保存しましたが、ピンまたは一覧の同期を完了できませんでした。"
                    : "予定は保存しましたが、最新状態を再読込できませんでした。"
            }
            reveal(created)
            return created
        } catch {
            errorMessage = managementErrorMessage(for: error, action: "保存")
            return nil
        }
    }

    @discardableResult
    func updateItem(
        _ event: CalendarEvent,
        with draft: CalendarItemDraft,
        scope: CalendarMutationScope
    ) -> CalendarEvent? {
        let updated: CalendarEvent
        do {
            updated = try source.updateItem(event, with: draft, scope: scope)
        } catch {
            errorMessage = managementErrorMessage(for: error, action: "保存")
            return nil
        }

        applyLocalReplacement(of: event, with: updated)
        errorMessage = nil
        do {
            try ensureCalendarVisible(updated.calendarID)
            try reloadAllEventWindowsOrThrow(additionalPinCandidates: [updated])
        } catch {
            errorMessage = "予定は保存しましたが、ピンまたは一覧の同期を完了できませんでした。"
        }
        return updated
    }

    @discardableResult
    func setTaskCompleted(
        _ event: CalendarEvent,
        completed: Bool,
        scope: CalendarMutationScope
    ) -> CalendarEvent? {
        let updated: CalendarEvent
        do {
            updated = try source.setTaskCompletion(event, completed: completed, scope: scope)
        } catch {
            errorMessage = managementErrorMessage(for: error, action: "更新")
            return nil
        }

        applyLocalReplacement(of: event, with: updated)
        errorMessage = nil
        do {
            try ensureCalendarVisible(updated.calendarID)
            try reloadAllEventWindowsOrThrow(additionalPinCandidates: [updated])
        } catch {
            errorMessage = "タスクは更新しましたが、ピンまたは一覧の同期を完了できませんでした。"
        }
        return updated
    }

    @discardableResult
    func deleteItem(_ event: CalendarEvent, scope: CalendarMutationScope) -> Bool {
        do {
            try source.deleteItem(event, scope: scope)
        } catch {
            errorMessage = managementErrorMessage(for: error, action: "削除")
            return false
        }

        events.removeAll { $0.id == event.id }
        upcomingEvents.removeAll { $0.id == event.id }
        if selectedEvent?.id == event.id { selectedEvent = nil }
        reconcileSelectedTag()
        errorMessage = nil
        do {
            try reloadAllEventWindowsOrThrow()
        } catch {
            errorMessage = "予定は削除しましたが、ピンまたは一覧の同期を完了できませんでした。"
        }
        return true
    }

    func event(for pin: PinnedEvent) -> CalendarEvent {
        if let exact = (events + upcomingEvents).first(where: { $0.id == pin.id }) {
            return exact
        }

        let allCalendarIDs = Set(
            (calendars.isEmpty ? source.availableCalendars : calendars).map(\.id)
        )
        if !allCalendarIDs.isEmpty {
            let interval = DateInterval(
                start: pin.startDate.addingTimeInterval(-1),
                end: max(pin.endDate, pin.startDate).addingTimeInterval(1)
            )
            if let candidates = try? source.events(in: interval, calendarIDs: allCalendarIDs) {
                let matches = candidates.filter { $0.id == pin.id }
                if matches.count == 1 {
                    return matches[0]
                }
            }
        }

        return CalendarEvent(
            id: pin.id,
            eventIdentifier: pin.eventIdentifier,
            externalIdentifier: pin.externalIdentifier,
            title: pin.title,
            startDate: pin.startDate,
            endDate: pin.endDate,
            isAllDay: pin.isAllDay,
            calendarName: pin.calendarName,
            calendarColorHex: pin.calendarColorHex,
            location: pin.location,
            recurrence: pin.recurrence,
            recurrenceTimeZoneIdentifier: pin.recurrenceTimeZoneIdentifier,
            isRecurring: pin.recurrence != nil,
            canEdit: false
        )
    }

    func open(_ url: URL) {
        guard url.scheme == "koyomi", url.host == "event" else { return }
        let id = url.pathComponents.dropFirst().joined(separator: "/").removingPercentEncoding ?? ""
        guard !id.isEmpty else { return }
        if selectDeepLinkedEvent(id: id) {
            pendingDeepLinkedEventID = nil
            pendingDeepLinkedPin = nil
        } else {
            pendingDeepLinkedEventID = id
            pendingDeepLinkedPin = cachedDeepLinkPinsByID[id]
        }
    }

    private func selectDeepLinkedEvent(id: String) -> Bool {
        if let event = (events + upcomingEvents).first(where: { $0.id == id }) {
            selectedEvent = event
            return true
        } else if let pin = pinnedEvents.first(where: { $0.id == id }) {
            selectedEvent = event(for: pin)
            return true
        }
        return false
    }

    private func refreshAvailableCalendars() {
        calendars = source.availableCalendars
        selectedCalendarIDs = calendarSelectionStore.loadSelection(availableCalendars: calendars)
    }

    private struct LegacyPinMigrationResult {
        let succeeded: Bool
        let pinCandidates: [CalendarEvent]
    }

    private func migrateLegacyPins() -> LegacyPinMigrationResult {
        guard let legacyPinStore else {
            return LegacyPinMigrationResult(succeeded: true, pinCandidates: [])
        }
        let legacyPins: [PinnedEvent]
        do {
            legacyPins = try legacyPinStore.loadMigrationState()
        } catch {
            return LegacyPinMigrationResult(succeeded: false, pinCandidates: [])
        }
        guard !legacyPins.isEmpty else {
            return LegacyPinMigrationResult(succeeded: true, pinCandidates: [])
        }

        let allCalendarIDs = Set(calendars.map(\.id))
        guard !allCalendarIDs.isEmpty else {
            return LegacyPinMigrationResult(succeeded: false, pinCandidates: [])
        }

        var remaining: [PinnedEvent] = []
        var eventsToMigrate: [(pin: PinnedEvent, event: CalendarEvent)] = []
        var pinCandidates: [CalendarEvent] = []
        var hadUnmigratablePin = false
        for pin in legacyPins {
            let event: CalendarEvent
            switch resolvePinnedEvent(pin, calendarIDs: allCalendarIDs) {
            case let .resolved(resolved):
                event = resolved
            case .missing:
                continue
            case .retry:
                remaining.append(pin)
                continue
            }
            if event.isPinned {
                pinCandidates.append(event)
                continue
            }
            guard event.canEdit else {
                hadUnmigratablePin = true
                continue
            }
            eventsToMigrate.append((pin, event))
        }

        // Consume legacy authority before touching EventKit so a crash cannot leave
        // a stale local pin that later resurrects a Calendar-side removal. A confirmed
        // pre-commit failure is re-queued below only after checking the postcondition.
        do {
            try legacyPinStore.saveMigrationState(remaining)
        } catch {
            return LegacyPinMigrationResult(succeeded: false, pinCandidates: [])
        }

        var failedMigrationPins: [PinnedEvent] = []
        for migration in eventsToMigrate {
            do {
                let updated = try source.setPinned(
                    migration.event,
                    pinned: true,
                    scope: .thisEvent
                )
                pinCandidates.append(updated)
            } catch {
                switch resolvePinnedEvent(migration.pin, calendarIDs: allCalendarIDs) {
                case let .resolved(current) where current.isPinned:
                    pinCandidates.append(current)
                default:
                    hadUnmigratablePin = true
                    failedMigrationPins.append(migration.pin)
                }
            }
        }
        if !failedMigrationPins.isEmpty {
            remaining.append(contentsOf: failedMigrationPins)
            do {
                try legacyPinStore.saveMigrationState(remaining)
            } catch {
                return LegacyPinMigrationResult(succeeded: false, pinCandidates: pinCandidates)
            }
        }
        return LegacyPinMigrationResult(
            succeeded: remaining.isEmpty && !hadUnmigratablePin,
            pinCandidates: pinCandidates
        )
    }

    private enum PinnedEventResolution {
        case resolved(CalendarEvent)
        case missing
        case retry
    }

    private func resolvePinnedEvent(
        _ pin: PinnedEvent,
        calendarIDs: Set<String>
    ) -> PinnedEventResolution {
        let exactInterval = DateInterval(
            start: pin.startDate.addingTimeInterval(-1),
            end: max(pin.endDate, pin.startDate).addingTimeInterval(1)
        )
        let occurrenceCandidates: [CalendarEvent]
        do {
            occurrenceCandidates = try source.events(in: exactInterval, calendarIDs: calendarIDs)
        } catch {
            return .retry
        }
        let exactCandidates = occurrenceCandidates.filter { $0.id == pin.id }
        if exactCandidates.count == 1 {
            return .resolved(exactCandidates[0])
        }
        if exactCandidates.count > 1 {
            return .retry
        }

        let eventIdentifier = pin.eventIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let externalIdentifier = pin.externalIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !externalIdentifier.isEmpty {
            let externalMatches = occurrenceCandidates.filter {
                $0.externalIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
                    == externalIdentifier
                    && abs($0.startDate.timeIntervalSince(pin.startDate)) < 1
            }
            if externalMatches.count == 1 {
                return .resolved(externalMatches[0])
            }
            if externalMatches.count > 1 {
                return .retry
            }
        }
        guard !eventIdentifier.isEmpty || !externalIdentifier.isEmpty else { return .missing }
        let tolerance: TimeInterval = 7 * 86_400
        let nearbyInterval = DateInterval(
            start: pin.startDate.addingTimeInterval(-tolerance - 1),
            end: max(pin.endDate, pin.startDate).addingTimeInterval(tolerance + 1)
        )
        let nearbyCandidates: [CalendarEvent]
        do {
            nearbyCandidates = try source.events(in: nearbyInterval, calendarIDs: calendarIDs)
                .filter {
                    // Recurring siblings can share an EventKit identifier. After an
                    // exact miss, treating one as a moved occurrence can pin the wrong day.
                    !$0.isRecurring
                        && ((!eventIdentifier.isEmpty && $0.eventIdentifier == eventIdentifier)
                            || (!externalIdentifier.isEmpty
                                && $0.externalIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
                                    == externalIdentifier))
                        && abs($0.startDate.timeIntervalSince(pin.startDate)) <= tolerance
                }
        } catch {
            return .retry
        }
        guard let nearestDistance = nearbyCandidates.map({
            abs($0.startDate.timeIntervalSince(pin.startDate))
        }).min() else {
            return .missing
        }
        let nearest = nearbyCandidates.filter {
            abs(abs($0.startDate.timeIntervalSince(pin.startDate)) - nearestDistance) < 0.001
        }
        guard nearest.count == 1 else { return .retry }
        return .resolved(nearest[0])
    }

    private func ensureCalendarVisible(_ calendarID: String) throws {
        guard !selectedCalendarIDs.contains(calendarID) else { return }
        var selection = selectedCalendarIDs
        selection.insert(calendarID)
        try calendarSelectionStore.saveSelection(selection)
        selectedCalendarIDs = selection
    }

    private func saveCalendarSelection(_ selection: Set<String>) {
        do {
            try calendarSelectionStore.saveSelection(selection)
            selectedCalendarIDs = selection
            reloadAllEventWindows()
        } catch {
            errorMessage = "カレンダーの表示設定を保存できませんでした。"
        }
    }

    private func reloadAllEventWindows(additionalPinCandidates: [CalendarEvent] = []) {
        do {
            try reloadAllEventWindowsOrThrow(additionalPinCandidates: additionalPinCandidates)
            errorMessage = nil
        } catch {
            errorMessage = "予定を読み込めませんでした。"
        }
    }

    private func reloadAllEventWindowsOrThrow(
        additionalPinCandidates: [CalendarEvent] = []
    ) throws {
        guard
            let selectedInterval = CalendarLoadWindow.interval(around: selectedDate, calendar: calendar),
            let upcomingInterval = CalendarLoadWindow.interval(
                around: now(),
                calendar: calendar,
                monthsBefore: 6,
                monthsAfter: 18
            ),
            let pinDiscoveryInterval = CalendarPin.discoveryInterval(
                around: now(),
                calendar: calendar
            )
        else { throw CalendarEventSourceError.invalidDraft }

        let selectedEvents = try source.events(
            in: selectedInterval,
            calendarIDs: selectedCalendarIDs
        )
        let futureEvents = try source.events(
            in: upcomingInterval,
            calendarIDs: selectedCalendarIDs
        )
        let pinCandidates = try source.events(
            in: pinDiscoveryInterval,
            calendarIDs: Set(calendars.map(\.id))
        )

        events = selectedEvents
        upcomingEvents = futureEvents
        loadedInterval = selectedInterval
        try replacePinnedSnapshots(
            with: selectedEvents + pinCandidates + additionalPinCandidates,
            recurrenceValidationInterval: pinDiscoveryInterval
        )
        reconcileSelectedTag()
        resolvePendingDeepLinkIfPossible()
    }

    private func loadSelectedEventWindow() {
        guard let interval = CalendarLoadWindow.interval(around: selectedDate, calendar: calendar) else {
            return
        }

        do {
            events = try source.events(in: interval, calendarIDs: selectedCalendarIDs)
            loadedInterval = interval
            reconcileSelectedTag()
            try reloadPinnedSnapshots(additionalCandidates: events)
            errorMessage = nil
        } catch {
            errorMessage = "予定を読み込めませんでした。"
        }
    }

    private func reloadPinnedSnapshots(additionalCandidates: [CalendarEvent]) throws {
        guard let interval = CalendarPin.discoveryInterval(
            around: now(),
            calendar: calendar
        ) else { throw CalendarEventSourceError.invalidDraft }
        let pinCandidates = try source.events(
            in: interval,
            calendarIDs: Set(calendars.map(\.id))
        )
        try replacePinnedSnapshots(
            with: additionalCandidates + pinCandidates,
            recurrenceValidationInterval: interval
        )
    }

    private func replacePinnedSnapshots(
        with candidates: [CalendarEvent],
        recurrenceValidationInterval: DateInterval
    ) throws {
        var authoritativeCandidates = candidates
        let candidateIDs = Set(candidates.map(\.id))
        let allCalendarIDs = Set(calendars.map(\.id))

        if !allCalendarIDs.isEmpty {
            for cachedPin in pinStore.load() where !candidateIDs.contains(cachedPin.id) {
                switch resolvePinnedEvent(
                    cachedPin,
                    calendarIDs: allCalendarIDs
                ) {
                case let .resolved(event):
                    authoritativeCandidates.append(event)
                case .missing:
                    continue
                case .retry:
                    throw CalendarEventSourceError.unsupported
                }
            }
        }

        let snapshots = CalendarPin.snapshots(
            from: authoritativeCandidates,
            at: now(),
            recurrenceValidationInterval: recurrenceValidationInterval,
            calendar: calendar
        )
        editablePinIDs = Set(
            authoritativeCandidates
                .filter { $0.isPinned && $0.canEdit }
                .map { $0.pinnedSnapshot.id }
        )
        pinnedEvents = snapshots
        try pinStore.save(snapshots)
        WidgetCenter.shared.reloadTimelines(ofKind: "KoyomiPinnedCountdown")
    }

    private func resolvePendingDeepLinkIfPossible() {
        guard let id = pendingDeepLinkedEventID else { return }
        let cachedPin = pendingDeepLinkedPin
        pendingDeepLinkedEventID = nil
        pendingDeepLinkedPin = nil
        if selectDeepLinkedEvent(id: id) { return }

        let allCalendarIDs = Set(calendars.map(\.id))
        guard
            let cachedPin,
            !allCalendarIDs.isEmpty,
            case let .resolved(event) = resolvePinnedEvent(
                cachedPin,
                calendarIDs: allCalendarIDs
            ),
            event.isPinned
        else { return }
        selectedEvent = event
    }

    private func reveal(_ event: CalendarEvent) {
        searchText = ""
        itemFilter = .all
        selectedTag = nil
        selectDate(event.startDate)
    }

    private func applyLocalCreation(_ event: CalendarEvent) {
        if !events.contains(where: { $0.id == event.id }) {
            events.append(event)
            events.sort(by: eventSort)
        }
        if !upcomingEvents.contains(where: { $0.id == event.id }) {
            upcomingEvents.append(event)
            upcomingEvents.sort(by: eventSort)
        }
        reconcileSelectedTag()
    }

    private func applyLocalReplacement(of original: CalendarEvent, with updated: CalendarEvent) {
        replace(original, with: updated, in: &events)
        replace(original, with: updated, in: &upcomingEvents)
        if selectedEvent?.id == original.id { selectedEvent = updated }
        reconcileSelectedTag()
    }

    private func replace(
        _ original: CalendarEvent,
        with updated: CalendarEvent,
        in collection: inout [CalendarEvent]
    ) {
        if let index = collection.firstIndex(where: { $0.id == original.id }) {
            collection[index] = updated
        } else if !collection.contains(where: { $0.id == updated.id }) {
            collection.append(updated)
        }
        collection.sort(by: eventSort)
    }

    private func eventSort(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        if lhs.endDate != rhs.endDate { return lhs.endDate < rhs.endDate }
        return lhs.id < rhs.id
    }

    private func managementErrorMessage(for error: Error, action: String) -> String {
        guard let sourceError = error as? CalendarEventSourceError else {
            return "予定を\(action)できませんでした。"
        }
        switch sourceError {
        case .invalidDraft:
            return "タイトル、日時、保存先Calendarを確認してください。"
        case .readOnlyCalendar:
            return "このCalendarは読み取り専用です。"
        case .notFound:
            return "予定が見つかりません。再読込してからやり直してください。"
        case .ambiguousMatch:
            return "対象を安全に特定できなかったため変更しませんでした。"
        case .conflict:
            return "予定が他の端末で変更されています。再読込して確認してください。"
        case .futureScopeUnavailable:
            return "「これ以降」は繰り返し予定だけで選べます。"
        case .unsupported:
            return "この予定の変更にはまだ対応していません。"
        }
    }

    private func reconcileSelectedTag() {
        selectedTag = EventTagIndex.resolvedSelection(
            selectedTag,
            availableTags: availableTags
        )
    }
}
