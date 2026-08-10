import Foundation

@MainActor
final class DemoCalendarSource: CalendarEventSource {
    let allEvents: [CalendarEvent]
    let seededPin: PinnedEvent
    let availableCalendars: [CalendarDescriptor]

    init(referenceDate: Date = .now, calendar: Calendar = .current) {
        let personal = CalendarDescriptor(
            id: "demo-personal",
            title: "個人",
            sourceName: "iCloud",
            colorHex: "21A179"
        )
        let work = CalendarDescriptor(
            id: "demo-work",
            title: "仕事",
            sourceName: "Google",
            colorHex: "5B8DEF"
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
                calendarID: descriptor.id,
                calendarName: descriptor.title,
                calendarColorHex: descriptor.colorHex,
                location: location
            )
        }

        let project = make(
            "project",
            title: "プロジェクト発表",
            start: date(tomorrow, hour: 10),
            end: date(tomorrow, hour: 11, minute: 30),
            calendar: work,
            location: "オンライン"
        )
        let allDay = make(
            "release-week",
            title: "リリース週",
            start: today,
            end: tomorrow,
            isAllDay: true,
            calendar: work
        )
        let focus = make(
            "focus",
            title: "集中作業",
            start: date(today, hour: 10),
            end: date(today, hour: 12),
            calendar: personal,
            location: "自宅"
        )
        let dentist = make(
            "dentist",
            title: "歯科検診",
            start: date(today, hour: 14),
            end: date(today, hour: 15),
            calendar: personal,
            location: "広島駅前"
        )
        let travel = make(
            "travel",
            title: "新幹線の予約",
            start: date(nextTrip, hour: 9),
            end: date(nextTrip, hour: 9, minute: 30),
            calendar: work
        )

        allEvents = [allDay, focus, dentist, project, travel]
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
}
