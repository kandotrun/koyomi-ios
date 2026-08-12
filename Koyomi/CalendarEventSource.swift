import Foundation

@MainActor
protocol CalendarEventSource: AnyObject {
    var authorizationStatus: CalendarAccessStatus { get }
    var availableCalendars: [CalendarDescriptor] { get }
    func requestFullAccess() async throws -> Bool
    func events(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarEvent]
    func createItem(_ draft: CalendarItemDraft) throws -> CalendarEvent
    func updateItem(
        _ event: CalendarEvent,
        with draft: CalendarItemDraft,
        scope: CalendarMutationScope
    ) throws -> CalendarEvent
    func setTaskCompletion(
        _ event: CalendarEvent,
        completed: Bool,
        scope: CalendarMutationScope
    ) throws -> CalendarEvent
    func setPinned(
        _ event: CalendarEvent,
        pinned: Bool,
        scope: CalendarMutationScope
    ) throws -> CalendarEvent
    func deleteItem(_ event: CalendarEvent, scope: CalendarMutationScope) throws
}

enum CalendarEventSourceError: Error, Equatable {
    case invalidDraft
    case readOnlyCalendar
    case notFound
    case ambiguousMatch
    case conflict
    case futureScopeUnavailable
    case unsupported
}

enum CalendarAccessStatus: Equatable {
    case notDetermined
    case fullAccess
    case denied
    case restricted
    case writeOnly
}
