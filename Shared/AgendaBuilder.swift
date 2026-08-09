import Foundation

public enum AgendaBuilder {
    public static func events(
        on day: Date,
        from events: [CalendarEvent],
        calendar: Calendar = .current
    ) -> [CalendarEvent] {
        let dayStart = calendar.startOfDay(for: day)
        guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }

        return events
            .filter { event in
                event.endDate > dayStart && event.startDate < nextDayStart
            }
            .sorted(by: eventSort)
    }

    private static func eventSort(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        if lhs.isAllDay != rhs.isAllDay {
            return lhs.isAllDay
        }
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }
        if lhs.title != rhs.title {
            return lhs.title < rhs.title
        }
        return lhs.id < rhs.id
    }
}
