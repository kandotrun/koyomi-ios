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
    public var notes: String?
    public var alarmOffsets: [TimeInterval]
    public var recurrence: CalendarRecurrenceRule?
    public var recurrenceTimeZoneIdentifier: String?
    public var isRecurring: Bool
    public var canEdit: Bool
    public var lastModifiedDate: Date?

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
        location: String?,
        notes: String? = nil,
        alarmOffsets: [TimeInterval] = [],
        recurrence: CalendarRecurrenceRule? = nil,
        recurrenceTimeZoneIdentifier: String? = nil,
        isRecurring: Bool = false,
        canEdit: Bool = false,
        lastModifiedDate: Date? = nil
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
        self.notes = notes
        self.alarmOffsets = alarmOffsets
        self.recurrence = recurrence
        self.recurrenceTimeZoneIdentifier = recurrenceTimeZoneIdentifier
        self.isRecurring = isRecurring
        self.canEdit = canEdit
        self.lastModifiedDate = lastModifiedDate
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
            location: location,
            recurrence: isRecurring ? recurrence : nil,
            recurrenceTimeZoneIdentifier: isRecurring ? recurrenceTimeZoneIdentifier : nil,
            recurrenceSeriesIdentifier: isRecurring
                ? CalendarPin.recurringSeriesIdentity(for: self)
                : nil,
            recurrenceAnchorDate: isRecurring ? startDate : nil
        )
    }
}
