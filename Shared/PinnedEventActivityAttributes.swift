#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

public struct PinnedEventActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public let title: String
        public let calendarName: String
        public let calendarColorHex: String
        public let startDate: Date
        public let isAllDay: Bool
        public let isEstimatedDateWindow: Bool

        public init(
            title: String,
            calendarName: String,
            calendarColorHex: String,
            startDate: Date,
            isAllDay: Bool,
            isEstimatedDateWindow: Bool
        ) {
            self.title = title
            self.calendarName = calendarName
            self.calendarColorHex = calendarColorHex
            self.startDate = startDate
            self.isAllDay = isAllDay
            self.isEstimatedDateWindow = isEstimatedDateWindow
        }
    }

    public let eventID: String
    public let scheduledStartDate: Date

    public init(eventID: String, scheduledStartDate: Date) {
        self.eventID = eventID
        self.scheduledStartDate = scheduledStartDate
    }
}
#endif
