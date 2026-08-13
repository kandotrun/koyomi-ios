import Foundation

public struct PinnedLiveActivityPlan: Equatable, Sendable {
    public let event: PinnedEvent
    public let activationDate: Date
    public let referenceDate: Date

    public init(event: PinnedEvent, activationDate: Date, referenceDate: Date) {
        self.event = event
        self.activationDate = activationDate
        self.referenceDate = referenceDate
    }

    public var startsImmediately: Bool {
        activationDate <= referenceDate
    }
}

public enum PinnedLiveActivityPolicy {
    public static let countdownWindow: TimeInterval = 12 * 3_600
    public static let maximumEventIDUTF8Bytes = 768
    public static let maximumTitleUTF8Bytes = 768
    public static let maximumCalendarNameUTF8Bytes = 256

    public static func plans(
        from events: [PinnedEvent],
        at referenceDate: Date = .now
    ) -> [PinnedLiveActivityPlan] {
        var eligibleByID: [String: PinnedEvent] = [:]
        for event in events where isEligible(event, at: referenceDate) {
            if let current = eligibleByID[event.id], current.startDate <= event.startDate {
                continue
            }
            eligibleByID[event.id] = event
        }

        return eligibleByID.values
            .sorted {
                if $0.startDate != $1.startDate { return $0.startDate < $1.startDate }
                return $0.id < $1.id
            }
            .map { event in
                PinnedLiveActivityPlan(
                    event: event,
                    activationDate: max(
                        referenceDate,
                        event.startDate.addingTimeInterval(-countdownWindow)
                    ),
                    referenceDate: referenceDate
                )
            }
    }

    public static func relevanceScore(
        for startDate: Date,
        at referenceDate: Date
    ) -> Double {
        let remaining = max(startDate.timeIntervalSince(referenceDate), 0)
        return max(0, min(1, 1 - remaining / countdownWindow))
    }

    public static func displayTitle(for event: PinnedEvent) -> String {
        truncatingUTF8(
            normalizingForActivity(event.titleMetadata.displayTitle),
            toAtMost: maximumTitleUTF8Bytes
        )
    }

    public static func calendarName(for event: PinnedEvent) -> String {
        truncatingUTF8(
            normalizingForActivity(event.calendarName),
            toAtMost: maximumCalendarNameUTF8Bytes
        )
    }

    private static func normalizingForActivity(_ value: String) -> String {
        var normalized = ""
        var previousWasWhitespace = false

        for scalar in value.unicodeScalars {
            let isWhitespaceOrControl = CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.controlCharacters.contains(scalar)
            if isWhitespaceOrControl {
                if !previousWasWhitespace, !normalized.isEmpty {
                    normalized.append(" ")
                }
                previousWasWhitespace = true
            } else {
                normalized.unicodeScalars.append(scalar)
                previousWasWhitespace = false
            }
        }

        return normalized.trimmingCharacters(in: .whitespaces)
    }

    private static func truncatingUTF8(_ value: String, toAtMost byteLimit: Int) -> String {
        guard value.utf8.count > byteLimit else { return value }

        var byteCount = 0
        var result = ""
        for character in value {
            let characterBytes = String(character).utf8.count
            guard byteCount + characterBytes <= byteLimit else { break }
            result.append(character)
            byteCount += characterBytes
        }
        return result
    }

    private static func isEligible(_ event: PinnedEvent, at referenceDate: Date) -> Bool {
        guard event.id.utf8.count <= maximumEventIDUTF8Bytes else { return false }
        guard event.startDate > referenceDate, event.endDate > referenceDate else { return false }
        if event.isEstimatedDateWindow {
            return event.isOpenEstimatedTask
        }
        return true
    }
}
