import Foundation

/// Minimal, local snapshot shared by the app and its widgets.
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
        location: String?
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
    }
}

public enum KoyomiSharedStorage {
    public static let keychainAccessGroup = "UGNVGWZMAU.run.kan.koyomi.shared"
    public static let keychainService = "run.kan.koyomi.shared-storage"
    public static let pinnedEventsKey = "pinned-events-v1"
}
