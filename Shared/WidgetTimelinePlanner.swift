import Foundation

public struct WidgetTimelineState: Equatable, Sendable {
    public let date: Date
    public let pins: [PinnedEvent]

    public init(date: Date, pins: [PinnedEvent]) {
        self.date = date
        self.pins = pins
    }
}

public enum WidgetTimelinePlanner {
    public static let defaultMaximumEntryCount = 64

    public static func states(
        from allPins: [PinnedEvent],
        at now: Date = .now,
        limit: Int,
        transitionOffset: TimeInterval = 2,
        maximumEntryCount: Int = defaultMaximumEntryCount
    ) -> [WidgetTimelineState] {
        guard limit > 0 else {
            return [WidgetTimelineState(date: now, pins: [])]
        }

        let timelinePins = PinnedRecurrenceExpander.expandedPins(from: allPins, at: now)
        let visible = WidgetPinSelector.activePins(from: timelinePins, at: now, limit: limit)
        var states = [WidgetTimelineState(date: now, pins: visible)]
        let safeTransitionOffset = normalizedTransitionOffset(transitionOffset)
        let safeMaximumEntryCount = max(maximumEntryCount, 1)
        var pendingTransitions = Set(
            timelinePins
                .filter { $0.endDate > now && $0.startDate > now }
                .map(\.startDate)
        )

        func addVisibleBoundaries(_ pins: [PinnedEvent], after date: Date) {
            for pin in pins {
                if pin.startDate > date {
                    pendingTransitions.insert(pin.startDate)
                }
                if pin.endDate > date {
                    pendingTransitions.insert(pin.endDate)
                }
                for boundary in CountdownProximityCalculator.futureBoundaryDates(
                    for: pin,
                    after: date
                ) {
                    pendingTransitions.insert(boundary)
                }
            }
        }

        addVisibleBoundaries(visible, after: now)

        while states.count < safeMaximumEntryCount,
              let transition = pendingTransitions.min() {
            pendingTransitions.remove(transition)
            let date = transition.addingTimeInterval(safeTransitionOffset)
            guard date > states[states.count - 1].date else { continue }

            let pins = WidgetPinSelector.activePins(from: timelinePins, at: date, limit: limit)
            states.append(WidgetTimelineState(date: date, pins: pins))

            pendingTransitions = Set(pendingTransitions.filter { $0 > date })
            addVisibleBoundaries(pins, after: date)
        }

        return states
    }

    static func normalizedTransitionOffset(_ transitionOffset: TimeInterval) -> TimeInterval {
        max(transitionOffset, 0)
    }
}
