import Foundation

public enum CountdownProximityTone: Equatable, Sendable {
    case calm
    case approaching
    case soon
    case urgent
    case attention
    case inactive
}

public struct CountdownProximityState: Equatable, Sendable {
    public let level: Int
    public let totalSegmentCount: Int
    public let label: String
    public let tone: CountdownProximityTone

    public init(
        level: Int,
        totalSegmentCount: Int = CountdownProximityCalculator.totalSegmentCount,
        label: String,
        tone: CountdownProximityTone
    ) {
        self.totalSegmentCount = max(totalSegmentCount, 1)
        self.level = min(max(level, 0), self.totalSegmentCount)
        self.label = label
        self.tone = tone
    }

    public var accessibilityDescription: String {
        "期限の近さ、\(label)、\(totalSegmentCount)段階中\(level)"
    }

    public var activeSegmentIndex: Int? {
        level == 0 ? nil : level - 1
    }
}

public enum CountdownProximityCalculator {
    public static let totalSegmentCount = 5

    private static let hour: TimeInterval = 3_600
    private static let day: TimeInterval = 86_400
    private static let thresholds: [(
        interval: TimeInterval,
        level: Int,
        label: String,
        tone: CountdownProximityTone
    )] = [
        (hour, 5, "まもなく", .urgent),
        (day, 4, "かなり近い", .soon),
        (7 * day, 3, "近い", .approaching),
        (30 * day, 2, "近づいています", .approaching)
    ]

    public static func state(
        for event: PinnedEvent,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CountdownProximityState {
        if event.isEstimatedDateWindow {
            return estimatedState(for: event, now: now, calendar: calendar)
        }

        let presentation = CountdownCalculator.presentation(for: event, now: now)
        guard let targetDate = presentation.targetDate else {
            return inactiveState(label: presentation.value)
        }
        return state(forRemainingInterval: targetDate.timeIntervalSince(now))
    }

    public static func futureBoundaryDates(
        for event: PinnedEvent,
        after date: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        guard let targetDate = targetDate(for: event, at: date, calendar: calendar) else { return [] }
        return thresholds
            .map { targetDate.addingTimeInterval(-$0.interval) }
            .filter { $0 > date }
    }

    private static func targetDate(
        for event: PinnedEvent,
        at date: Date,
        calendar: Calendar
    ) -> Date? {
        if event.isEstimatedDateWindow {
            guard event.isOpenEstimatedTask,
                  let window = CalendarEstimatedWindow(event: event, calendar: calendar)
            else { return nil }
            return switch window.status(at: date, calendar: calendar) {
            case .upcoming: window.startDate
            case .withinWindow, .overdue: nil
            }
        }
        if date < event.startDate { return event.startDate }
        if date < event.endDate { return event.endDate }
        return nil
    }

    private static func estimatedState(
        for event: PinnedEvent,
        now: Date,
        calendar: Calendar
    ) -> CountdownProximityState {
        guard event.isOpenEstimatedTask,
              let window = CalendarEstimatedWindow(event: event, calendar: calendar)
        else { return inactiveState(label: "完了") }

        return switch window.status(at: now, calendar: calendar) {
        case .upcoming:
            state(forRemainingInterval: window.startDate.timeIntervalSince(now))
        case .withinWindow:
            CountdownProximityState(
                level: 4,
                label: "見込み期間内",
                tone: .soon
            )
        case .overdue:
            CountdownProximityState(
                level: totalSegmentCount,
                label: "要確認",
                tone: .attention
            )
        }
    }

    private static func state(forRemainingInterval interval: TimeInterval) -> CountdownProximityState {
        let remaining = max(interval, 0)
        if let band = thresholds.first(where: { remaining <= $0.interval }) {
            return CountdownProximityState(
                level: band.level,
                label: band.label,
                tone: band.tone
            )
        }
        return CountdownProximityState(
            level: 1,
            label: "余裕あり",
            tone: .calm
        )
    }

    private static func inactiveState(label: String) -> CountdownProximityState {
        CountdownProximityState(
            level: 0,
            label: label,
            tone: .inactive
        )
    }
}
