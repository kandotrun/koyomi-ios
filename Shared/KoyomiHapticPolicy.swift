public enum KoyomiInteraction: CaseIterable, Equatable, Sendable {
    case selectDate
    case switchAgenda
    case changeCalendarFilter
    case openEvent
    case togglePin
    case refresh
    case requestAccess
    case dismiss
}

public enum KoyomiHapticFeedback: Equatable, Sendable {
    case selection
    case impact
}

public enum KoyomiHapticPolicy {
    public static func feedback(for interaction: KoyomiInteraction) -> KoyomiHapticFeedback {
        switch interaction {
        case .togglePin:
            return .impact
        case .selectDate, .switchAgenda, .changeCalendarFilter, .openEvent, .refresh, .requestAccess, .dismiss:
            return .selection
        }
    }
}
