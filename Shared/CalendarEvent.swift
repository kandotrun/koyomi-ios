import Foundation

public struct CalendarEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var eventIdentifier: String
    public var externalIdentifier: String?
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var calendarID: String
    public var calendarName: String
    public var calendarColorHex: String
    public var location: String?

    public init(
        id: String,
        eventIdentifier: String,
        externalIdentifier: String?,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarID: String = "",
        calendarName: String,
        calendarColorHex: String,
        location: String?
    ) {
        self.id = id
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.calendarName = calendarName
        self.calendarColorHex = calendarColorHex
        self.location = location
    }

    public var pinnedSnapshot: PinnedEvent {
        PinnedEvent(
            id: EventOccurrenceID.make(
                eventIdentifier: eventIdentifier,
                externalIdentifier: externalIdentifier,
                startDate: startDate
            ),
            eventIdentifier: eventIdentifier,
            externalIdentifier: externalIdentifier,
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            calendarName: calendarName,
            calendarColorHex: calendarColorHex,
            location: location
        )
    }
}
