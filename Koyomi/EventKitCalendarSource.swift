import EventKit
import Foundation
import UIKit

@MainActor
final class EventKitCalendarSource: CalendarEventSource {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    var authorizationStatus: CalendarAccessStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .fullAccess, .authorized:
            return .fullAccess
        case .writeOnly:
            return .writeOnly
        @unknown default:
            return .denied
        }
    }

    func requestFullAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    func events(in interval: DateInterval) throws -> [CalendarEvent] {
        guard authorizationStatus == .fullAccess else { return [] }

        let predicate = eventStore.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: nil
        )

        return eventStore.events(matching: predicate).map { event in
            let eventIdentifier = event.eventIdentifier ?? ""
            let externalIdentifier = event.calendarItemExternalIdentifier
            let occurrenceID = EventOccurrenceID.make(
                eventIdentifier: eventIdentifier,
                externalIdentifier: externalIdentifier,
                startDate: event.startDate
            )
            let rawTitle = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let rawLocation = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)

            return CalendarEvent(
                id: occurrenceID,
                eventIdentifier: eventIdentifier,
                externalIdentifier: externalIdentifier,
                title: rawTitle.isEmpty ? "名称未設定" : rawTitle,
                startDate: event.startDate,
                endDate: max(event.endDate, event.startDate),
                isAllDay: event.isAllDay,
                calendarName: event.calendar.title,
                calendarColorHex: Self.hex(event.calendar.cgColor),
                location: rawLocation?.isEmpty == false ? rawLocation : nil
            )
        }
    }

    private static func hex(_ cgColor: CGColor) -> String {
        let color = UIColor(cgColor: cgColor)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "4F7DF3"
        }
        return String(
            format: "%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}
