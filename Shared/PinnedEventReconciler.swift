import Foundation

public enum PinnedEventReconciler {
    public static func reconcile(
        pins: [PinnedEvent],
        with events: [CalendarEvent],
        movedOccurrenceTolerance: TimeInterval = 7 * 86_400
    ) -> [PinnedEvent] {
        var exactByID: [String: CalendarEvent] = [:]
        for event in events where exactByID[event.id] == nil {
            exactByID[event.id] = event
        }

        return pins.map { pin in
            if let exact = exactByID[pin.id] {
                return exact.pinnedSnapshot
            }
            guard !pin.eventIdentifier.isEmpty else { return pin }

            let nearest = events
                .filter { $0.eventIdentifier == pin.eventIdentifier }
                .min { lhs, rhs in
                    let lhsDistance = abs(lhs.startDate.timeIntervalSince(pin.startDate))
                    let rhsDistance = abs(rhs.startDate.timeIntervalSince(pin.startDate))
                    if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                    return lhs.id < rhs.id
                }

            guard let nearest else { return pin }
            let distance = abs(nearest.startDate.timeIntervalSince(pin.startDate))
            guard distance <= movedOccurrenceTolerance else { return pin }
            return nearest.pinnedSnapshot
        }
    }
}
