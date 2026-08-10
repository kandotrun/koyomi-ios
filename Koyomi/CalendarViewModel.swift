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
        AgendaBuilder.events(on: selectedDate, from: events, calendar: calendar)
    }

    var upcomingSections: [UpcomingAgendaSection] {
        UpcomingAgendaBuilder.sections(from: upcomingEvents, now: now(), calendar: calendar)
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

    func event(for pin: PinnedEvent) -> CalendarEvent {
        if let exact = (events + upcomingEvents).first(where: { $0.id == pin.id }) {
            return exact
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
            location: pin.location
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
        guard
            let selectedInterval = CalendarLoadWindow.interval(around: selectedDate, calendar: calendar),
            let upcomingInterval = CalendarLoadWindow.interval(
                around: now(),
                calendar: calendar,
                monthsBefore: 0,
                monthsAfter: 18
            )
        else { return }

        do {
            events = try source.events(in: selectedInterval, calendarIDs: selectedCalendarIDs)
            upcomingEvents = try source.events(in: upcomingInterval, calendarIDs: selectedCalendarIDs)
            loadedInterval = selectedInterval
            reconcilePins(with: events + upcomingEvents)
            errorMessage = nil
        } catch {
            errorMessage = "予定を読み込めませんでした。"
        }
    }

    private func loadSelectedEventWindow() {
        guard let interval = CalendarLoadWindow.interval(around: selectedDate, calendar: calendar) else {
            return
        }

        do {
            events = try source.events(in: interval, calendarIDs: selectedCalendarIDs)
            loadedInterval = interval
            reconcilePins(with: events + upcomingEvents)
            errorMessage = nil
        } catch {
            errorMessage = "予定を読み込めませんでした。"
        }
    }

    private func reconcilePins(with candidates: [CalendarEvent]) {
        let reconciled = PinnedEventReconciler.reconcile(pins: pinnedEvents, with: candidates)

        guard reconciled != pinnedEvents else { return }
        do {
            try pinStore.save(reconciled)
            pinnedEvents = pinStore.load()
            WidgetCenter.shared.reloadTimelines(ofKind: "KoyomiPinnedCountdown")
        } catch {
            errorMessage = "ピン留めの更新を保存できませんでした。"
        }
    }
}
