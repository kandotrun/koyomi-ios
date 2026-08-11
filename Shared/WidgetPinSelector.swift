import Foundation

public enum WidgetPinSelector {
    public static func activePinCount(
        from events: [PinnedEvent],
        at now: Date = .now
    ) -> Int {
        events.lazy.filter { isVisible($0, at: now) }.count
    }

    public static func activePins(
        from events: [PinnedEvent],
        at now: Date = .now,
        limit: Int
    ) -> [PinnedEvent] {
        guard limit > 0 else { return [] }

        return events
            .filter { isVisible($0, at: now) }
            .sorted { lhs, rhs in
                let lhsOngoing = lhs.startDate <= now
                let rhsOngoing = rhs.startDate <= now
                if lhsOngoing != rhsOngoing { return lhsOngoing }
                if lhsOngoing, lhs.endDate != rhs.endDate { return lhs.endDate < rhs.endDate }
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.id < rhs.id
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func isVisible(_ event: PinnedEvent, at now: Date) -> Bool {
        if event.isEstimatedDateWindow {
            return event.isOpenEstimatedTask
        }
        return event.endDate > now
    }
}

public enum EventOccurrenceID {
    public static func make(
        eventIdentifier: String,
        externalIdentifier: String?,
        startDate: Date
    ) -> String {
        let rawIdentity: String
        if !eventIdentifier.isEmpty {
            rawIdentity = eventIdentifier
        } else if let externalIdentifier, !externalIdentifier.isEmpty {
            rawIdentity = externalIdentifier
        } else {
            rawIdentity = "event"
        }

        let encodedIdentity = Data(rawIdentity.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let milliseconds = Int64((startDate.timeIntervalSince1970 * 1_000).rounded())
        return "\(encodedIdentity).\(milliseconds)"
    }
}
