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
    private let calendarSelectionStore: CalendarSelectionStore
    private let calendar: Calendar
    private let now: () -> Date
    private var loadedInterval: DateInterval?

    init(
        source: CalendarEventSource,
        pinStore: PinnedEventsStore,
        calendarSelectionStore: CalendarSelectionStore,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.source = source
        self.pinStore = pinStore
        self.calendarSelectionStore = calendarSelectionStore
        self.calendar = calendar
        self.now = now
        authorizationStatus = source.authorizationStatus
        pinnedEvents = pinStore.load()
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
        pinnedEvents = pinStore.load()
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
                reloadAllEventWindows()
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
        reloadAllEventWindows()
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
        pinnedEvents.contains { $0.id == event.pinnedSnapshot.id }
    }

    func togglePin(_ event: CalendarEvent) {
        do {
            pinnedEvents = try pinStore.toggle(event.pinnedSnapshot)
            WidgetCenter.shared.reloadTimelines(ofKind: "KoyomiPinnedCountdown")
        } catch {
            errorMessage = "ピン留めを保存できませんでした。"
        }
    }

    func removePin(_ pin: PinnedEvent) {
        do {
            pinnedEvents = try pinStore.remove(id: pin.id)
            WidgetCenter.shared.reloadTimelines(ofKind: "KoyomiPinnedCountdown")
        } catch {
            errorMessage = "ピン留めを解除できませんでした。"
        }
    }

    @discardableResult
    func createItem(_ draft: CalendarItemDraft) -> CalendarEvent? {
        do {
            let created = try source.createItem(draft)
            applyLocalCreation(created)
            var postSaveIssue = false
            errorMessage = nil
            if draft.dateMode == .estimatedWindow, !isPinned(created) {
                do {
                    pinnedEvents = try pinStore.toggle(created.pinnedSnapshot)
                    WidgetCenter.shared.reloadTimelines(ofKind: "KoyomiPinnedCountdown")
                } catch {
                    postSaveIssue = true
                }
            }
            do {
                try ensureCalendarVisible(created.calendarID)
                try reloadAllEventWindowsOrThrow()
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
            try replacePinIfNeeded(for: event, with: updated)
            try ensureCalendarVisible(updated.calendarID)
            try reloadAllEventWindowsOrThrow()
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
            try replacePinIfNeeded(for: event, with: updated)
            try ensureCalendarVisible(updated.calendarID)
            try reloadAllEventWindowsOrThrow()
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
            try removePinsIfNeeded(for: event, scope: scope)
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
            canEdit: false
        )
    }

    func open(_ url: URL) {
        guard url.scheme == "koyomi", url.host == "event" else { return }
        let id = url.pathComponents.dropFirst().joined(separator: "/").removingPercentEncoding ?? ""
        if let event = (events + upcomingEvents).first(where: { $0.id == id }) {
            selectedEvent = event
        } else if let pin = pinnedEvents.first(where: { $0.id == id }) {
            selectedEvent = event(for: pin)
        }
    }

    private func refreshAvailableCalendars() {
        calendars = source.availableCalendars
        selectedCalendarIDs = calendarSelectionStore.loadSelection(availableCalendars: calendars)
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

    private func reloadAllEventWindows() {
        do {
            try reloadAllEventWindowsOrThrow()
            errorMessage = nil
        } catch {
            errorMessage = "予定を読み込めませんでした。"
        }
    }

    private func reloadAllEventWindowsOrThrow() throws {
        guard
            let selectedInterval = CalendarLoadWindow.interval(around: selectedDate, calendar: calendar),
            let upcomingInterval = CalendarLoadWindow.interval(
                around: now(),
                calendar: calendar,
                monthsBefore: 6,
                monthsAfter: 18
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
        let reconciledPins = PinnedEventReconciler.reconcile(
            pins: pinnedEvents,
            with: selectedEvents + futureEvents
        )
        if reconciledPins != pinnedEvents {
            try pinStore.save(reconciledPins)
        }

        events = selectedEvents
        upcomingEvents = futureEvents
        loadedInterval = selectedInterval
        pinnedEvents = reconciledPins
        reconcileSelectedTag()
        WidgetCenter.shared.reloadTimelines(ofKind: "KoyomiPinnedCountdown")
    }

    private func loadSelectedEventWindow() {
        guard let interval = CalendarLoadWindow.interval(around: selectedDate, calendar: calendar) else {
            return
        }

        do {
            events = try source.events(in: interval, calendarIDs: selectedCalendarIDs)
            loadedInterval = interval
            reconcileSelectedTag()
            try reconcilePins(with: events + upcomingEvents)
            errorMessage = nil
        } catch {
            errorMessage = "予定を読み込めませんでした。"
        }
    }

    private func reconcilePins(with candidates: [CalendarEvent]) throws {
        let reconciled = PinnedEventReconciler.reconcile(pins: pinnedEvents, with: candidates)
        guard reconciled != pinnedEvents else { return }
        try pinStore.save(reconciled)
        pinnedEvents = reconciled
        WidgetCenter.shared.reloadTimelines(ofKind: "KoyomiPinnedCountdown")
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

    private func replacePinIfNeeded(
        for original: CalendarEvent,
        with updated: CalendarEvent
    ) throws {
        guard let index = pinnedEvents.firstIndex(where: { $0.id == original.pinnedSnapshot.id }) else {
            return
        }
        var pins = pinnedEvents
        pins[index] = updated.pinnedSnapshot
        try pinStore.save(pins)
        pinnedEvents = pins
        WidgetCenter.shared.reloadTimelines(ofKind: "KoyomiPinnedCountdown")
    }

    private func removePinsIfNeeded(
        for event: CalendarEvent,
        scope: CalendarMutationScope
    ) throws {
        let pins = PinnedEventDeletionPolicy.remainingPins(
            afterDeleting: event,
            scope: scope,
            from: pinnedEvents
        )
        guard pins != pinnedEvents else { return }
        try pinStore.save(pins)
        pinnedEvents = pins
        WidgetCenter.shared.reloadTimelines(ofKind: "KoyomiPinnedCountdown")
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
