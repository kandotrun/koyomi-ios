import Foundation

/// Minimal, derived snapshot shared by the app and its widgets.
/// Calendar title `#ピン` metadata remains the source of truth.
/// It intentionally excludes notes, attendees, URLs, and alarms.
public struct PinnedEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var eventIdentifier: String
    public var externalIdentifier: String?
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var calendarName: String
    public var calendarColorHex: String
    public var location: String?
    public var recurrence: CalendarRecurrenceRule?
    public var recurrenceTimeZoneIdentifier: String?
    public var recurrenceSeriesIdentifier: String?
    public var recurrenceAnchorDate: Date?
    public var recurrenceValidatedThroughDate: Date?

    public init(
        id: String,
        eventIdentifier: String,
        externalIdentifier: String?,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarName: String,
        calendarColorHex: String,
        location: String?,
        recurrence: CalendarRecurrenceRule? = nil,
        recurrenceTimeZoneIdentifier: String? = nil,
        recurrenceSeriesIdentifier: String? = nil,
        recurrenceAnchorDate: Date? = nil,
        recurrenceValidatedThroughDate: Date? = nil
    ) {
        self.id = id
        self.eventIdentifier = eventIdentifier
        self.externalIdentifier = externalIdentifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarName = calendarName
        self.calendarColorHex = calendarColorHex
        self.location = location
        self.recurrence = recurrence
        self.recurrenceTimeZoneIdentifier = recurrenceTimeZoneIdentifier
        self.recurrenceSeriesIdentifier = recurrenceSeriesIdentifier
        self.recurrenceAnchorDate = recurrenceAnchorDate
        self.recurrenceValidatedThroughDate = recurrenceValidatedThroughDate
    }
}

public enum KoyomiSharedStorage {
    public static let keychainAccessGroup = "UGNVGWZMAU.run.kan.koyomi.shared"
    public static let keychainService = "run.kan.koyomi.shared-storage"
    public static let pinnedEventSnapshotsKey = "pinned-event-snapshots-v2"
    public static let legacyPinnedEventsKey = "pinned-events-v1"
}
