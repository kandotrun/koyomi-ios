import Foundation

public enum CalendarItemFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case events
    case estimatedWindows
    case openTasks
    case completedTasks

    public var id: Self { self }
}

public enum CalendarItemQuery {
    public static func events(
        from events: [CalendarEvent],
        searchText: String,
        filter: CalendarItemFilter
    ) -> [CalendarEvent] {
        let terms = searchText
            .split(whereSeparator: \.isWhitespace)
            .map { normalized(String($0)) }
            .filter { !$0.isEmpty }

        return events.filter { event in
            guard matchesFilter(event, filter: filter) else { return false }
            guard !terms.isEmpty else { return true }

            let metadata = event.titleMetadata
            let searchable = [
                event.title,
                metadata.displayTitle,
                metadata.tags.joined(separator: " "),
                event.calendarName,
                event.location ?? "",
                event.notes ?? ""
            ]
            .map(normalized)
            .joined(separator: " ")

            return terms.allSatisfy(searchable.contains)
        }
    }

    private static func matchesFilter(
        _ event: CalendarEvent,
        filter: CalendarItemFilter
    ) -> Bool {
        switch filter {
        case .all:
            return true
        case .events:
            return event.managementKind == .event
        case .estimatedWindows:
            return event.isEstimatedDateWindow
        case .openTasks:
            return event.managementKind == .task && !event.isCompletedTask
        case .completedTasks:
            return event.managementKind == .task && event.isCompletedTask
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "ja_JP")
            )
            .lowercased()
    }
}
