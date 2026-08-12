import Foundation

public enum CalendarPin {
    public static let tag = "ピン"

    /// EventKit truncates a single event predicate to four years. Keep this
    /// discovery window within that documented limit and favor future pins.
    public static func discoveryInterval(
        around date: Date,
        calendar: Calendar = .current
    ) -> DateInterval? {
        CalendarLoadWindow.interval(
            around: date,
            calendar: calendar,
            monthsBefore: 6,
            monthsAfter: 42
        )
    }

    public static func isPinned(title: String) -> Bool {
        EventTitleMetadata.parse(title).containsTag(tag)
    }

    public static let maximumRecurringOccurrencesPerSeries = 32

    public static func snapshots(
        from events: [CalendarEvent],
        at referenceDate: Date = .now,
        recurrenceValidationInterval: DateInterval? = nil,
        calendar: Calendar = .current
    ) -> [PinnedEvent] {
        var eventsByID: [String: CalendarEvent] = [:]
        for event in events {
            eventsByID[event.pinnedSnapshot.id] = event
        }

        let uniqueEvents = Array(eventsByID.values)
        var retained = uniqueEvents.filter { !$0.isRecurring && $0.isPinned }
        let recurringIdentities = Set(
            uniqueEvents.filter(\.isRecurring).map(recurringSeriesIdentity(for:))
        )
        let recurring = Dictionary(grouping: uniqueEvents.filter {
            recurringIdentities.contains(recurringSeriesIdentity(for: $0))
        }) {
            recurringSeriesIdentity(for: $0)
        }
        for occurrences in recurring.values {
            retained.append(contentsOf: occurrences.filter {
                $0.isRecurring && $0.isPinned
            }.sorted {
                let lhsVisible = $0.endDate > referenceDate
                let rhsVisible = $1.endDate > referenceDate
                if lhsVisible != rhsVisible { return lhsVisible }
                if lhsVisible {
                    if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
                } else if $0.startDate != $1.startDate {
                    return $0.startDate > $1.startDate
                }
                return $0.id < $1.id
            }.prefix(maximumRecurringOccurrencesPerSeries))
        }

        let anchors = recurring.reduce(into: [String: Date]()) { result, entry in
            result[entry.key] = entry.value.filter {
                $0.isRecurring && $0.isPinned
            }.map(\.startDate).min()
        }
        let validatedThroughDates = recurring.reduce(into: [String: Date]()) { result, entry in
            guard let recurrenceValidationInterval else { return }
            result[entry.key] = PinnedRecurrenceExpander.validatedThroughDate(
                for: entry.value,
                in: recurrenceValidationInterval,
                calendar: calendar
            )
        }
        return retained.map { event in
            var snapshot = event.pinnedSnapshot
            if event.isRecurring {
                let identity = recurringSeriesIdentity(for: event)
                snapshot.recurrenceAnchorDate = anchors[identity]
                snapshot.recurrenceValidatedThroughDate = validatedThroughDates[identity]
            }
            return snapshot
        }.sorted {
            if $0.startDate == $1.startDate { return $0.id < $1.id }
            return $0.startDate < $1.startDate
        }
    }

    static func recurringSeriesIdentity(for event: CalendarEvent) -> String {
        let externalIdentifier = event.externalIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = externalIdentifier?.isEmpty == false
            ? externalIdentifier!
            : event.eventIdentifier
        return "\(event.calendarID)\u{1F}\(identity)"
    }
}

extension CalendarEvent {
    public var isPinned: Bool {
        CalendarPin.isPinned(title: title)
    }
}