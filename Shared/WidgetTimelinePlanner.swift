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
    public static func states(
        from allPins: [PinnedEvent],
        at now: Date = .now,
        limit: Int,
        transitionOffset: TimeInterval = 2
    ) -> [WidgetTimelineState] {
        let visible = WidgetPinSelector.activePins(from: allPins, at: now, limit: limit)
        let transitions = Set(
            visible
                .flatMap { [$0.startDate, $0.endDate] }
                .filter { $0 > now }
        ).sorted()

        let current = WidgetTimelineState(date: now, pins: visible)
        let future = transitions.map { transition -> WidgetTimelineState in
            let date = transition.addingTimeInterval(transitionOffset)
            return WidgetTimelineState(
                date: date,
                pins: WidgetPinSelector.activePins(from: allPins, at: date, limit: limit)
            )
        }
        return [current] + future
    }
}
