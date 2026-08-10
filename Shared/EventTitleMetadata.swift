import Foundation

public struct EventTitleMetadata: Equatable, Sendable {
    public let displayTitle: String
    public let tags: [String]

    public init(displayTitle: String, tags: [String]) {
        self.displayTitle = displayTitle
        self.tags = tags
    }

    public static func parse(_ rawTitle: String) -> EventTitleMetadata {
        var titleTokens: [String] = []
        var tags: [String] = []
        var normalizedTags: Set<String> = []

        for component in rawTitle.split(whereSeparator: \.isWhitespace) {
            let token = String(component)
            guard let tag = tag(from: token) else {
                titleTokens.append(token)
                continue
            }

            if normalizedTags.insert(normalize(tag)).inserted {
                tags.append(tag)
            }
        }

        let displayTitle = titleTokens.joined(separator: " ")
        return EventTitleMetadata(
            displayTitle: displayTitle.isEmpty ? "無題の予定" : displayTitle,
            tags: tags
        )
    }

    public func containsTag(_ candidate: String) -> Bool {
        let normalizedCandidate = Self.normalize(candidate)
        return tags.contains { Self.normalize($0) == normalizedCandidate }
    }

    static func normalize(_ tag: String) -> String {
        tag.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func tag(from token: String) -> String? {
        guard token.first == "#" else { return nil }

        let punctuation = CharacterSet(charactersIn: "、。,.!?！？:：;；)]}）】」』…")
        var value = String(token.dropFirst())
        while let last = value.last,
              last.unicodeScalars.allSatisfy({ punctuation.contains($0) }) {
            value.removeLast()
        }
        return value.isEmpty ? nil : value
    }
}

public enum EventTagIndex {
    private static let preferredOrder = [
        EventTitleMetadata.normalize("重要"): 0,
        EventTitleMetadata.normalize("タスク"): 1,
        EventTitleMetadata.normalize("仕事"): 2,
        EventTitleMetadata.normalize("メモ"): 3,
    ]

    public static func tags(in events: [CalendarEvent]) -> [String] {
        var tags: [String] = []
        var normalizedTags: Set<String> = []

        for tag in events.flatMap({ $0.titleMetadata.tags }) {
            if normalizedTags.insert(EventTitleMetadata.normalize(tag)).inserted {
                tags.append(tag)
            }
        }

        return tags.sorted { lhs, rhs in
            let lhsNormalized = EventTitleMetadata.normalize(lhs)
            let rhsNormalized = EventTitleMetadata.normalize(rhs)
            let lhsOrder = preferredOrder[lhsNormalized] ?? 100
            let rhsOrder = preferredOrder[rhsNormalized] ?? 100

            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            let comparison = lhs.localizedCaseInsensitiveCompare(rhs)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return lhs < rhs
        }
    }

    public static func events(from events: [CalendarEvent], matching selectedTag: String?) -> [CalendarEvent] {
        guard let selectedTag else { return events }
        let normalizedSelection = normalizedSelection(selectedTag)
        guard !normalizedSelection.isEmpty else { return events }

        return events.filter { event in
            event.titleMetadata.tags.contains {
                EventTitleMetadata.normalize($0) == normalizedSelection
            }
        }
    }

    public static func resolvedSelection(
        _ selectedTag: String?,
        availableTags: [String]
    ) -> String? {
        guard let selectedTag else { return nil }
        let normalized = normalizedSelection(selectedTag)
        guard !normalized.isEmpty else { return nil }
        return availableTags.first { EventTitleMetadata.normalize($0) == normalized }
    }

    public static func stablePaletteIndex(for tag: String, paletteCount: Int) -> Int {
        guard paletteCount > 0 else { return 0 }
        return EventTitleMetadata.normalize(tag).utf8.reduce(0) { value, byte in
            (value * 31 + Int(byte)) % paletteCount
        }
    }

    private static func normalizedSelection(_ selectedTag: String) -> String {
        EventTitleMetadata.normalize(
            String(
                selectedTag.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingPrefix("#")
            )
        )
    }
}

public enum EventTagAnimationPolicy {
    public static func shouldAnimate(reduceMotionEnabled: Bool) -> Bool {
        !reduceMotionEnabled
    }
}

extension CalendarEvent {
    public var titleMetadata: EventTitleMetadata {
        EventTitleMetadata.parse(title)
    }
}

extension PinnedEvent {
    public var titleMetadata: EventTitleMetadata {
        EventTitleMetadata.parse(title)
    }
}
