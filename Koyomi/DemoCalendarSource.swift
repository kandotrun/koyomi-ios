import Foundation

@MainActor
final class DemoCalendarSource: CalendarEventSource {
    private(set) var allEvents: [CalendarEvent]
    let seededPin: PinnedEvent
    let availableCalendars: [CalendarDescriptor]
    private let shouldFailMutations: Bool

    init(
        referenceDate: Date = .now,
        calendar: Calendar = .current,
        shouldFailMutations: Bool = false,
        hasReadOnlyPinnedEvent: Bool = false,
        hasRecurringPinnedEvent: Bool = false
    ) {
        self.shouldFailMutations = shouldFailMutations
        let personal = CalendarDescriptor(
            id: "demo-personal",
            title: "個人",
            sourceName: "iCloud",
            colorHex: "21A179",
            allowsContentModifications: !hasReadOnlyPinnedEvent
        )
        let work = CalendarDescriptor(
            id: "demo-work",
            title: "仕事",
            sourceName: "Google",
            colorHex: "5B8DEF",
            allowsContentModifications: true
        )
        availableCalendars = [personal, work]

        let today = calendar.startOfDay(for: referenceDate)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let nextTrip = calendar.date(byAdding: .day, value: 10, to: today)!

        func date(_ base: Date, hour: Int, minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
        }

        func make(
            _ key: String,
            title: String,
            start: Date,
            end: Date,
            isAllDay: Bool = false,
            calendar descriptor: CalendarDescriptor,
            location: String? = nil,
            recurrence: CalendarRecurrenceRule? = nil
        ) -> CalendarEvent {
            let eventIdentifier = "demo-\(key)"
            let externalIdentifier = "demo-external-\(key)"
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
                endDate: end,
                isAllDay: isAllDay,
                calendarID: descriptor.id,
                calendarName: descriptor.title,
                calendarColorHex: descriptor.colorHex,
                location: location,
                recurrence: recurrence,
                isRecurring: recurrence != nil,
                canEdit: descriptor.allowsContentModifications
            )
        }

        let project = make(
            "project",
            title: "プロジェクト発表 #仕事 #重要 #ピン",
            start: date(tomorrow, hour: 10),
            end: date(tomorrow, hour: 11, minute: 30),
            calendar: work,
            location: "オンライン"
        )
        let allDay = make(
            "release-week",
            title: "リリース週 #仕事",
            start: today,
            end: tomorrow,
            isAllDay: true,
            calendar: work
        )
        let focus = make(
            "focus",
            title: "集中作業 #仕事 #タスク",
            start: date(today, hour: 10),
            end: date(today, hour: 12),
            calendar: personal,
            location: "自宅"
        )
        let dentist = make(
            "dentist",
            title: hasReadOnlyPinnedEvent ? "歯科検診 #個人 #ピン" : "歯科検診 #個人",
            start: date(today, hour: 14),
            end: date(today, hour: 15),
            calendar: personal,
            location: "広島駅前"
        )
        let travel = make(
            "travel",
            title: "新幹線の予約 #タスク #旅行",
            start: date(nextTrip, hour: 9),
            end: date(nextTrip, hour: 9, minute: 30),
            calendar: work
        )
        let estimatedCenter = calendar.date(byAdding: .month, value: 1, to: today) ?? nextTrip
        let estimatedWindow = CalendarEstimatedWindow.centered(
            on: estimatedCenter,
            bufferDays: 14,
            calendar: calendar
        )
        let engraving = make(
            "engraving",
            title: "指輪の刻印が完了 #タスク #見込み #重要 #個人",
            start: estimatedWindow?.startDate ?? nextTrip,
            end: estimatedWindow?.endDate ?? (calendar.date(byAdding: .day, value: 1, to: nextTrip) ?? nextTrip),
            isAllDay: true,
            calendar: personal,
            location: "ブルガリア"
        )

        let recurringPin = make(
            "daily-pin",
            title: "毎日の確認 #個人 #ピン",
            start: referenceDate.addingTimeInterval(-15 * 60),
            end: referenceDate.addingTimeInterval(45 * 60),
            calendar: personal,
            recurrence: CalendarRecurrenceRule(frequency: .daily)
        )

        allEvents = [allDay, focus, dentist, project, travel, engraving]
        if hasRecurringPinnedEvent {
            allEvents.append(recurringPin)
        }
        seededPin = project.pinnedSnapshot
    }

    var authorizationStatus: CalendarAccessStatus { .fullAccess }

    func requestFullAccess() async throws -> Bool { true }

    func events(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEvent] {
        allEvents.filter {
            calendarIDs.contains($0.calendarID)
                && $0.endDate > interval.start
                && $0.startDate < interval.end
        }
    }

    func createItem(_ draft: CalendarItemDraft) throws -> CalendarEvent {
        if shouldFailMutations { throw CalendarEventSourceError.unsupported }
        guard let descriptor = writableCalendar(id: draft.calendarID),
              !draft.readableTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.endDate > draft.startDate,
              draft.hasValidDateModeShape()
        else { throw CalendarEventSourceError.invalidDraft }

        let identifier = "demo-created-\(UUID().uuidString)"
        let event = CalendarEvent(
            id: EventOccurrenceID.make(
                eventIdentifier: identifier,
                externalIdentifier: nil,
                startDate: draft.startDate
            ),
            eventIdentifier: identifier,
            externalIdentifier: nil,
            title: ManagedCalendarTitle.make(
                readableTitle: draft.readableTitle,
                kind: draft.kind,
                dateMode: draft.dateMode,
                isImportant: draft.isImportant,
                isCompleted: draft.isCompleted,
                tags: draft.tags
            ),
            startDate: draft.startDate,
            endDate: draft.endDate,
            isAllDay: draft.isAllDay,
            calendarID: descriptor.id,
            calendarName: descriptor.title,
            calendarColorHex: descriptor.colorHex,
            location: draft.location,
            notes: draft.notes,
            alarmOffsets: draft.alarmOffsets,
            recurrence: draft.recurrence,
            isRecurring: draft.recurrence != nil,
            canEdit: true,
            lastModifiedDate: .now
        )
        allEvents.append(event)
        return event
    }

    func updateItem(
        _ event: CalendarEvent,
        with draft: CalendarItemDraft,
        scope: CalendarMutationScope
    ) throws -> CalendarEvent {
        if shouldFailMutations { throw CalendarEventSourceError.unsupported }
        guard scope == .thisEvent || event.isRecurring else {
            throw CalendarEventSourceError.futureScopeUnavailable
        }
        guard let descriptor = writableCalendar(id: draft.calendarID),
              !draft.readableTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.endDate > draft.startDate,
              draft.hasValidDateModeShape()
        else { throw CalendarEventSourceError.invalidDraft }
        let index = try exactIndex(for: event)
        var updated = allEvents[index]
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
        updated.calendarID = descriptor.id
        updated.calendarName = descriptor.title
        updated.calendarColorHex = descriptor.colorHex
        updated.location = draft.location
        updated.notes = draft.notes
        updated.alarmOffsets = draft.alarmOffsets
        updated.recurrence = draft.recurrence
        updated.isRecurring = draft.recurrence != nil
        updated.lastModifiedDate = .now
        updated.id = EventOccurrenceID.make(
            eventIdentifier: updated.eventIdentifier,
            externalIdentifier: updated.externalIdentifier,
            startDate: updated.startDate
        )
        allEvents[index] = updated
        return updated
    }

    func setTaskCompletion(
        _ event: CalendarEvent,
        completed: Bool,
        scope: CalendarMutationScope
    ) throws -> CalendarEvent {
        if shouldFailMutations { throw CalendarEventSourceError.unsupported }
        guard event.managementKind == .task else {
            throw CalendarEventSourceError.invalidDraft
        }
        guard scope == .thisEvent || event.isRecurring else {
            throw CalendarEventSourceError.futureScopeUnavailable
        }
        let index = try exactIndex(for: event)
        var updated = allEvents[index]
        updated.title = EventTitleTagMutator.applying(
            EventTitleTagChange(
                adding: completed ? ["完了"] : [],
                removing: completed ? [] : ["完了"]
            ),
            to: updated.title
        )
        updated.lastModifiedDate = .now
        allEvents[index] = updated
        return updated
    }

    func setPinned(
        _ event: CalendarEvent,
        pinned: Bool,
        scope: CalendarMutationScope
    ) throws -> CalendarEvent {
        if shouldFailMutations { throw CalendarEventSourceError.unsupported }
        guard scope == .thisEvent || event.isRecurring else {
            throw CalendarEventSourceError.futureScopeUnavailable
        }
        let index = try exactIndex(for: event)
        guard writableCalendar(id: allEvents[index].calendarID) != nil else {
            throw CalendarEventSourceError.readOnlyCalendar
        }
        var updated = allEvents[index]
        updated.title = EventTitleTagMutator.applying(
            EventTitleTagChange(
                adding: pinned ? [CalendarPin.tag] : [],
                removing: pinned ? [] : [CalendarPin.tag]
            ),
            to: updated.title
        )
        updated.lastModifiedDate = .now
        allEvents[index] = updated
        return updated
    }

    func deleteItem(_ event: CalendarEvent, scope: CalendarMutationScope) throws {
        if shouldFailMutations { throw CalendarEventSourceError.unsupported }
        guard scope == .thisEvent || event.isRecurring else {
            throw CalendarEventSourceError.futureScopeUnavailable
        }
        allEvents.remove(at: try exactIndex(for: event))
    }

    private func exactIndex(for event: CalendarEvent) throws -> Int {
        guard let reference = CalendarEventReference(event) else {
            throw CalendarEventSourceError.notFound
        }
        let resolved: CalendarEvent
        do {
            resolved = try reference.resolve(in: allEvents)
        } catch CalendarEventReferenceError.notFound {
            throw CalendarEventSourceError.notFound
        } catch {
            throw CalendarEventSourceError.ambiguousMatch
        }
        guard let index = allEvents.firstIndex(of: resolved) else {
            throw CalendarEventSourceError.notFound
        }
        return index
    }

    private func writableCalendar(id: String) -> CalendarDescriptor? {
        availableCalendars.first { $0.id == id && $0.allowsContentModifications }
    }
}
