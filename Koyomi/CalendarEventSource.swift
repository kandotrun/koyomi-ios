import Foundation

@MainActor
protocol CalendarEventSource: AnyObject {
    var authorizationStatus: CalendarAccessStatus { get }
    func requestFullAccess() async throws -> Bool
    func events(in interval: DateInterval) throws -> [CalendarEvent]
}

enum CalendarAccessStatus: Equatable {
    case notDetermined
    case fullAccess
    case denied
    case restricted
    case writeOnly
}
