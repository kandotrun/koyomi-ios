import Foundation

public enum CountdownPhase: Equatable, Sendable {
    case upcoming
    case ongoing
    case overdue
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
        if event.isEstimatedDateWindow {
            guard event.isOpenEstimatedTask else {
                return CountdownPresentation(
                    phase: .ended,
                    label: "完了",
                    value: "完了",
                    targetDate: nil
                )
            }
            if let estimated = estimatedPresentation(for: event, now: now) {
                return estimated
            }
        }
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

    public static func compactText(for event: PinnedEvent, now: Date = .now) -> String {
        let presentation = presentation(for: event, now: now)

        if event.isEstimatedDateWindow {
            return switch presentation.phase {
            case .upcoming:
                "見込みまで\(presentation.value)"
            case .ongoing:
                "遅くとも\(presentation.value)"
            case .overdue:
                "\(presentation.value)超過"
            case .ended:
                presentation.value
            }
        }

        switch presentation.phase {
        case .upcoming:
            guard let targetDate = presentation.targetDate,
                  let duration = compactDuration(targetDate.timeIntervalSince(now))
            else { return "まもなく" }
            return "あと\(duration)"
        case .ongoing:
            guard let targetDate = presentation.targetDate,
                  let duration = compactDuration(targetDate.timeIntervalSince(now))
            else { return "まもなく終了" }
            return "終了まで\(duration)"
        case .overdue:
            return "\(presentation.value)超過"
        case .ended:
            return presentation.value
        }
    }

    private static func estimatedPresentation(
        for event: PinnedEvent,
        now: Date,
        calendar: Calendar = .current
    ) -> CountdownPresentation? {
        guard let window = CalendarEstimatedWindow(event: event, calendar: calendar) else { return nil }
        switch window.status(at: now, calendar: calendar) {
        case let .upcoming(daysUntilStart):
            return CountdownPresentation(
                phase: .upcoming,
                label: "見込み期間まで",
                value: "\(daysUntilStart)日",
                targetDate: window.startDate
            )
        case let .withinWindow(daysUntilLatest):
            return CountdownPresentation(
                phase: .ongoing,
                label: "見込み期間内・遅くとも",
                value: "\(daysUntilLatest)日",
                targetDate: window.latestDate
            )
        case let .overdue(days):
            return CountdownPresentation(
                phase: .overdue,
                label: "要確認・超過",
                value: "\(days)日",
                targetDate: nil
            )
        }
    }

    private static func compactDuration(_ interval: TimeInterval) -> String? {
        let seconds = max(0, interval)
        if seconds >= 86_400 {
            return "\(max(1, Int(seconds / 86_400)))日"
        }
        if seconds >= 3_600 {
            return "\(max(1, Int(ceil(seconds / 3_600))))時間"
        }
        if seconds >= 60 {
            return "\(max(1, Int(ceil(seconds / 60))))分"
        }
        return nil
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
