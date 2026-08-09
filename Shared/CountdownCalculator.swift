import Foundation

public enum CountdownPhase: Equatable, Sendable {
    case upcoming
    case ongoing
    case ended
}

public struct CountdownPresentation: Equatable, Sendable {
    public let phase: CountdownPhase
    public let label: String
    public let value: String
    public let targetDate: Date?

    public init(phase: CountdownPhase, label: String, value: String, targetDate: Date?) {
        self.phase = phase
        self.label = label
        self.value = value
        self.targetDate = targetDate
    }
}

public enum CountdownCalculator {
    public static func presentation(for event: PinnedEvent, now: Date = .now) -> CountdownPresentation {
        if now < event.startDate {
            return CountdownPresentation(
                phase: .upcoming,
                label: "あと",
                value: format(event.startDate.timeIntervalSince(now)),
                targetDate: event.startDate
            )
        }

        if now < event.endDate {
            return CountdownPresentation(
                phase: .ongoing,
                label: "開催中・終了まで",
                value: format(event.endDate.timeIntervalSince(now)),
                targetDate: event.endDate
            )
        }

        return CountdownPresentation(
            phase: .ended,
            label: "終了",
            value: "終了",
            targetDate: nil
        )
    }

    private static func format(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded(.down)))
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if days > 0 {
            return String(format: "%d日 %02d:%02d:%02d", days, hours, minutes, seconds)
        }
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
