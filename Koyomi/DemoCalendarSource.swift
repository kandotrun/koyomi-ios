import Foundation

@MainActor
final class DemoCalendarSource: CalendarEventSource {
    let allEvents: [CalendarEvent]
    let seededPin: PinnedEvent

    init(referenceDate: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: referenceDate)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        func date(_ base: Date, hour: Int, minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
        }

        func make(
            _ key: String,
            title: String,
            start: Date,
            end: Date,
            isAllDay: Bool = false,
            color: String,
            location: String? = nil
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
                calendarName: "Kan",
                calendarColorHex: color,
                location: location
            )
        }

        let project = make(
            "project",
            title: "プロジェクト発表",
            start: date(tomorrow, hour: 10),
            end: date(tomorrow, hour: 11, minute: 30),
            color: "5B8DEF",
            location: "オンライン"
        )
        let allDay = make(
            "release-week",
            title: "リリース週",
            start: today,
            end: tomorrow,
            isAllDay: true,
            color: "8D6AE8"
        )
        let focus = make(
            "focus",
            title: "集中作業",
            start: date(today, hour: 10),
            end: date(today, hour: 12),
            color: "21A179",
            location: "自宅"
        )
        let dentist = make(
            "dentist",
            title: "歯科検診",
            start: date(today, hour: 14),
            end: date(today, hour: 15),
            color: "F08A5D",
            location: "広島駅前"
        )

        allEvents = [allDay, focus, dentist, project]
        seededPin = project.pinnedSnapshot
    }

    var authorizationStatus: CalendarAccessStatus { .fullAccess }

    func requestFullAccess() async throws -> Bool { true }

    func events(in interval: DateInterval) throws -> [CalendarEvent] {
        allEvents.filter { $0.endDate > interval.start && $0.startDate < interval.end }
    }
}
