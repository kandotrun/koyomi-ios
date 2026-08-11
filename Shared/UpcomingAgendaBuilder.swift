import Foundation

public struct UpcomingAgendaSection: Equatable, Identifiable, Sendable {
    public let day: Date
    public let events: [CalendarEvent]

    public var id: Date { day }

    public init(day: Date, events: [CalendarEvent]) {
        self.day = day
        self.events = events
    }
}

public enum UpcomingAgendaBuilder {
    public static func sections(
        from events: [CalendarEvent],
        now: Date,
        calendar: Calendar = .current
    ) -> [UpcomingAgendaSection] {
        let today = calendar.startOfDay(for: now)
        let activeEvents = events
            .filter {
                if $0.isEstimatedDateWindow {
                    return !$0.isCompletedTask
                }
                return $0.endDate > now
            }
            .sorted(by: eventComesFirst)

        let grouped = Dictionary(grouping: activeEvents) { event in
            max(calendar.startOfDay(for: event.startDate), today)
        }

        return grouped.keys.sorted().map { day in
            UpcomingAgendaSection(day: day, events: grouped[day] ?? [])
        }
    }

    private static func eventComesFirst(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        if lhs.title != rhs.title { return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending }
        return lhs.id < rhs.id
    }
}
