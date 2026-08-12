import EventKit
import Foundation
import UIKit

@MainActor
final class EventKitCalendarSource: CalendarEventSource {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    var authorizationStatus: CalendarAccessStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .fullAccess, .authorized:
            return .fullAccess
        case .writeOnly:
            return .writeOnly
        @unknown default:
            return .denied
        }
    }

    var availableCalendars: [CalendarDescriptor] {
        guard authorizationStatus == .fullAccess else { return [] }
        return eventStore.calendars(for: .event)
            .map(Self.calendarDescriptor(from:))
            .sorted { lhs, rhs in
                if lhs.sourceName != rhs.sourceName {
                    return lhs.sourceName.localizedStandardCompare(rhs.sourceName) == .orderedAscending
                }
                if lhs.title != rhs.title {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.id < rhs.id
            }
    }

    func requestFullAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    func events(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEvent] {
        guard authorizationStatus == .fullAccess, !calendarIDs.isEmpty else { return [] }

        let selectedCalendars = eventStore.calendars(for: .event).filter {
            calendarIDs.contains($0.calendarIdentifier)
        }
        guard !selectedCalendars.isEmpty else { return [] }

        let predicate = eventStore.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: selectedCalendars
        )
        return eventStore.events(matching: predicate).map(Self.calendarEvent(from:))
    }

    func createItem(_ draft: CalendarItemDraft) throws -> CalendarEvent {
        try validate(draft)
        guard draft.recurrence?.isFullyRepresentable != false else {
            throw CalendarEventSourceError.unsupported
        }
        let calendar = try writableCalendar(id: draft.calendarID)
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        apply(draft, to: event, replacingTitle: true)
        try eventStore.save(event, span: .thisEvent, commit: true)
        return Self.calendarEvent(from: event)
    }

    func updateItem(
        _ event: CalendarEvent,
        with draft: CalendarItemDraft,
        scope: CalendarMutationScope
    ) throws -> CalendarEvent {
        try validate(draft)
        let stored = try storedEvent(matching: event)
        try validateCurrentRevision(stored, against: event)
        guard stored.calendar.allowsContentModifications else {
            throw CalendarEventSourceError.readOnlyCalendar
        }
        try validateUnsupportedRecurrenceMutation(draft, original: event)
        try validateAlarmMutation(draft, stored: stored, original: event)
        let targetCalendar = try writableCalendar(id: draft.calendarID)
        let span = try eventKitSpan(scope, for: stored)

        let readableTitleChanged = draft.readableTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            != event.titleMetadata.displayTitle
        let desired = ManagedCalendarTitle.make(
            readableTitle: draft.readableTitle,
            kind: draft.kind,
            dateMode: draft.dateMode,
            isImportant: draft.isImportant,
            isCompleted: draft.isCompleted,
            tags: draft.tags
        )
        if readableTitleChanged {
            stored.title = EventTitleTagMutator.replacingReadableText(
                in: stored.title ?? "",
                with: draft.readableTitle
            )
        }
        let currentTags = stored.title.map(EventTitleMetadata.parse)?.tags ?? []
        let desiredTags = EventTitleMetadata.parse(desired).tags
        let currentIdentities = Set(currentTags.map(EventTitleMetadata.normalize))
        let desiredIdentities = Set(desiredTags.map(EventTitleMetadata.normalize))
        let additions = desiredTags.filter { !currentIdentities.contains(EventTitleMetadata.normalize($0)) }
        let removals = currentTags.filter { !desiredIdentities.contains(EventTitleMetadata.normalize($0)) }
        stored.title = EventTitleTagMutator.applying(
            EventTitleTagChange(adding: additions, removing: removals),
            to: stored.title ?? ""
        )

        stored.calendar = targetCalendar
        applyNonTitleFields(draft, to: stored, original: event)
        try eventStore.save(stored, span: span, commit: true)
        return Self.calendarEvent(from: stored)
    }

    func setTaskCompletion(
        _ event: CalendarEvent,
        completed: Bool,
        scope: CalendarMutationScope
    ) throws -> CalendarEvent {
        guard event.managementKind == .task else {
            throw CalendarEventSourceError.invalidDraft
        }
        let stored = try storedEvent(matching: event)
        try validateCurrentRevision(stored, against: event)
        guard stored.calendar.allowsContentModifications else {
            throw CalendarEventSourceError.readOnlyCalendar
        }
        let span = try eventKitSpan(scope, for: stored)
        stored.title = EventTitleTagMutator.applying(
            EventTitleTagChange(
                adding: completed ? ["完了"] : [],
                removing: completed ? [] : ["完了"]
            ),
            to: stored.title ?? ""
        )
        try eventStore.save(stored, span: span, commit: true)
        return Self.calendarEvent(from: stored)
    }

    func setPinned(
        _ event: CalendarEvent,
        pinned: Bool,
        scope: CalendarMutationScope
    ) throws -> CalendarEvent {
        let stored = try storedEvent(matching: event)
        try validateCurrentRevision(stored, against: event)
        guard stored.calendar.allowsContentModifications else {
            throw CalendarEventSourceError.readOnlyCalendar
        }
        let span = try eventKitSpan(scope, for: stored)
        stored.title = EventTitleTagMutator.applying(
            EventTitleTagChange(
                adding: pinned ? [CalendarPin.tag] : [],
                removing: pinned ? [] : [CalendarPin.tag]
            ),
            to: stored.title ?? ""
        )
        try eventStore.save(stored, span: span, commit: true)
        return Self.calendarEvent(from: stored)
    }

    func deleteItem(_ event: CalendarEvent, scope: CalendarMutationScope) throws {
        let stored = try storedEvent(matching: event)
        try validateCurrentRevision(stored, against: event)
        guard stored.calendar.allowsContentModifications else {
            throw CalendarEventSourceError.readOnlyCalendar
        }
        let span = try eventKitSpan(scope, for: stored)
        try eventStore.remove(stored, span: span, commit: true)
    }

    private func validate(_ draft: CalendarItemDraft) throws {
        guard !draft.readableTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              draft.endDate > draft.startDate,
              !draft.calendarID.isEmpty,
              draft.hasValidDateModeShape()
        else { throw CalendarEventSourceError.invalidDraft }
    }

    private func writableCalendar(id: String) throws -> EKCalendar {
        guard let calendar = eventStore.calendars(for: .event).first(where: {
            $0.calendarIdentifier == id
        }) else {
            throw CalendarEventSourceError.notFound
        }
        guard calendar.allowsContentModifications else {
            throw CalendarEventSourceError.readOnlyCalendar
        }
        return calendar
    }

    private func storedEvent(matching event: CalendarEvent) throws -> EKEvent {
        guard let reference = CalendarEventReference(event) else {
            throw CalendarEventSourceError.notFound
        }
        guard let calendar = eventStore.calendars(for: .event).first(where: {
            $0.calendarIdentifier == reference.calendarID
        }) else {
            throw CalendarEventSourceError.notFound
        }

        let margin: TimeInterval = 1
        let predicate = eventStore.predicateForEvents(
            withStart: event.startDate.addingTimeInterval(-margin),
            end: max(event.endDate, event.startDate).addingTimeInterval(margin),
            calendars: [calendar]
        )
        let storedCandidates = eventStore.events(matching: predicate)
        let modelCandidates = storedCandidates.map(Self.calendarEvent(from:))
        let resolved: CalendarEvent
        do {
            resolved = try reference.resolve(in: modelCandidates)
        } catch CalendarEventReferenceError.notFound {
            throw CalendarEventSourceError.notFound
        } catch {
            throw CalendarEventSourceError.ambiguousMatch
        }

        guard let index = modelCandidates.firstIndex(of: resolved) else {
            throw CalendarEventSourceError.notFound
        }
        return storedCandidates[index]
    }

    private func validateCurrentRevision(_ stored: EKEvent, against event: CalendarEvent) throws {
        guard (stored.title ?? "") == event.title else {
            throw CalendarEventSourceError.conflict
        }
        if let expected = event.lastModifiedDate,
           let current = stored.lastModifiedDate,
           abs(current.timeIntervalSince(expected)) >= 0.001 {
            throw CalendarEventSourceError.conflict
        }
    }

    private func eventKitSpan(_ scope: CalendarMutationScope, for event: EKEvent) throws -> EKSpan {
        switch scope {
        case .thisEvent:
            return .thisEvent
        case .futureEvents:
            guard event.hasRecurrenceRules else {
                throw CalendarEventSourceError.futureScopeUnavailable
            }
            return .futureEvents
        }
    }

    private func validateUnsupportedRecurrenceMutation(
        _ draft: CalendarItemDraft,
        original: CalendarEvent
    ) throws {
        let involvesUnsupportedRule = original.recurrence?.isFullyRepresentable == false
            || draft.recurrence?.isFullyRepresentable == false
        guard involvesUnsupportedRule, draft.recurrence != original.recurrence else { return }
        throw CalendarEventSourceError.unsupported
    }

    private func validateAlarmMutation(
        _ draft: CalendarItemDraft,
        stored: EKEvent,
        original: CalendarEvent
    ) throws {
        guard !CalendarAlarmOffsets.equivalent(original.alarmOffsets, draft.alarmOffsets),
              stored.alarms?.contains(where: { $0.absoluteDate != nil }) == true
        else { return }
        throw CalendarEventSourceError.unsupported
    }

    private func apply(_ draft: CalendarItemDraft, to event: EKEvent, replacingTitle: Bool) {
        if replacingTitle {
            event.title = ManagedCalendarTitle.make(
                readableTitle: draft.readableTitle,
                kind: draft.kind,
                dateMode: draft.dateMode,
                isImportant: draft.isImportant,
                isCompleted: draft.isCompleted,
                tags: draft.tags
            )
        }
        applyNonTitleFields(draft, to: event, original: nil)
    }

    private func applyNonTitleFields(
        _ draft: CalendarItemDraft,
        to event: EKEvent,
        original: CalendarEvent?
    ) {
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay
        event.location = normalizedOptional(draft.location)
        event.notes = normalizedOptional(draft.notes)
        if original == nil
            || !CalendarAlarmOffsets.equivalent(original?.alarmOffsets ?? [], draft.alarmOffsets) {
            event.alarms = draft.alarmOffsets.map(EKAlarm.init(relativeOffset:))
        }

        if original?.recurrence != draft.recurrence || original == nil {
            event.recurrenceRules = draft.recurrence.map { [Self.eventKitRecurrence(from: $0)] }
        }
    }

    private func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func calendarDescriptor(from calendar: EKCalendar) -> CalendarDescriptor {
        CalendarDescriptor(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            sourceName: calendar.source.title,
            colorHex: hex(calendar.cgColor),
            allowsContentModifications: calendar.allowsContentModifications
        )
    }

    private static func calendarEvent(from event: EKEvent) -> CalendarEvent {
        let eventIdentifier = event.eventIdentifier ?? ""
        let externalIdentifier = event.calendarItemExternalIdentifier
        let startDate = event.startDate ?? .distantPast
        let endDate = normalizedEndDate(for: event, startDate: startDate)
        let recurrenceRules = event.recurrenceRules ?? []
        return CalendarEvent(
            id: EventOccurrenceID.make(
                eventIdentifier: eventIdentifier,
                externalIdentifier: externalIdentifier,
                startDate: startDate
            ),
            eventIdentifier: eventIdentifier,
            externalIdentifier: externalIdentifier,
            title: event.title ?? "",
            startDate: startDate,
            endDate: endDate,
            isAllDay: event.isAllDay,
            calendarID: event.calendar.calendarIdentifier,
            calendarName: event.calendar.title,
            calendarColorHex: hex(event.calendar.cgColor),
            location: event.location,
            notes: event.notes,
            alarmOffsets: event.alarms?.map(\.relativeOffset) ?? [],
            recurrence: recurrenceRules.first.map {
                recurrence(from: $0, isOnlyRule: recurrenceRules.count == 1)
            },
            recurrenceTimeZoneIdentifier: event.timeZone?.identifier,
            isRecurring: event.hasRecurrenceRules,
            canEdit: event.calendar.allowsContentModifications
                && (!eventIdentifier.isEmpty || externalIdentifier?.isEmpty == false),
            lastModifiedDate: event.lastModifiedDate
        )
    }

    private static func normalizedEndDate(for event: EKEvent, startDate: Date) -> Date {
        let rawEnd = max(event.endDate ?? startDate, startDate)
        guard event.isAllDay else { return rawEnd }
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: rawEnd)
        guard rawEnd > endDay else { return rawEnd }
        return calendar.date(byAdding: .day, value: 1, to: endDay) ?? rawEnd
    }

    private static func eventKitRecurrence(from recurrence: CalendarRecurrenceRule) -> EKRecurrenceRule {
        let frequency: EKRecurrenceFrequency = switch recurrence.frequency {
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
        let weekdays = recurrence.weekdays.compactMap { weekday -> EKRecurrenceDayOfWeek? in
            guard let eventKitWeekday = EKWeekday(rawValue: weekday.rawValue) else { return nil }
            return EKRecurrenceDayOfWeek(eventKitWeekday)
        }
        let end: EKRecurrenceEnd?
        if let occurrenceCount = recurrence.occurrenceCount {
            end = EKRecurrenceEnd(occurrenceCount: occurrenceCount)
        } else if let endDate = recurrence.endDate {
            end = EKRecurrenceEnd(end: endDate)
        } else {
            end = nil
        }
        return EKRecurrenceRule(
            recurrenceWith: frequency,
            interval: recurrence.interval,
            daysOfTheWeek: weekdays.isEmpty ? nil : weekdays,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }

    private static func recurrence(
        from rule: EKRecurrenceRule,
        isOnlyRule: Bool
    ) -> CalendarRecurrenceRule {
        let frequency: CalendarRecurrenceFrequency
        let hasKnownFrequency: Bool
        switch rule.frequency {
        case .daily:
            frequency = .daily
            hasKnownFrequency = true
        case .weekly:
            frequency = .weekly
            hasKnownFrequency = true
        case .monthly:
            frequency = .monthly
            hasKnownFrequency = true
        case .yearly:
            frequency = .yearly
            hasKnownFrequency = true
        @unknown default:
            frequency = .daily
            hasKnownFrequency = false
        }

        let eventKitWeekdays = rule.daysOfTheWeek ?? []
        let weekdays = eventKitWeekdays.compactMap {
            CalendarRecurrenceWeekday(rawValue: $0.dayOfTheWeek.rawValue)
        }
        let hasUnsupportedWeekdayShape = eventKitWeekdays.contains { $0.weekNumber != 0 }
            || (frequency != .weekly && !eventKitWeekdays.isEmpty)
        let hasAdvancedComponents = rule.daysOfTheMonth?.isEmpty == false
            || rule.monthsOfTheYear?.isEmpty == false
            || rule.weeksOfTheYear?.isEmpty == false
            || rule.daysOfTheYear?.isEmpty == false
            || rule.setPositions?.isEmpty == false
        let rawOccurrenceCount = rule.recurrenceEnd?.occurrenceCount
        let occurrenceCount = rawOccurrenceCount.flatMap { $0 > 0 ? $0 : nil }

        return CalendarRecurrenceRule(
            frequency: frequency,
            interval: rule.interval,
            weekdays: weekdays,
            endDate: rule.recurrenceEnd?.endDate,
            occurrenceCount: occurrenceCount,
            isFullyRepresentable: isOnlyRule
                && hasKnownFrequency
                && !hasUnsupportedWeekdayShape
                && !hasAdvancedComponents
        )
    }

    private static func hex(_ cgColor: CGColor) -> String {
        let color = UIColor(cgColor: cgColor)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "4F7DF3"
        }
        return String(
            format: "%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}
