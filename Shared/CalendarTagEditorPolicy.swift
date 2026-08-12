import Foundation

/// Keeps tag-editor interactions deterministic while Calendar titles remain
/// the only persisted source of truth.
public enum CalendarTagEditorPolicy {
    public static let defaultSuggestions = ["仕事", "個人", "家族", "メモ", "ピン"]
    public static let editorManagedTags = ["タスク", "重要", "完了", "見込み"]

    public static func adding(input: String, to selectedTags: [String]) -> [String] {
        adding(input: input, to: selectedTags, excludedTags: editorManagedTags)
    }

    public static func adding(
        input: String,
        to selectedTags: [String],
        excludedTags: [String]
    ) -> [String] {
        var result = normalizedUnique(selectedTags)
        var identities = Set(result.map(EventTitleMetadata.normalize))
        let editorManagedIdentities = Set(excludedTags.map(EventTitleMetadata.normalize))

        for tag in parsedTags(from: input) {
            let identity = EventTitleMetadata.normalize(tag)
            // Existing Calendar tags remain visible/removable, but semantic
            // management tags must be created through their dedicated controls.
            guard !editorManagedIdentities.contains(identity) else { continue }
            guard identities.insert(identity).inserted else { continue }
            result.append(tag)
        }
        return result
    }

    public static func removing(_ tag: String, from selectedTags: [String]) -> [String] {
        let identity = EventTitleMetadata.normalize(tag)
        return normalizedUnique(selectedTags).filter {
            EventTitleMetadata.normalize($0) != identity
        }
    }

    public static func suggestions(
        availableTags: [String],
        selectedTags: [String],
        excludedTags: [String] = editorManagedTags
    ) -> [String] {
        let selected = Set(selectedTags.map(EventTitleMetadata.normalize))
        let excluded = Set(excludedTags.map(EventTitleMetadata.normalize))
        var identities: Set<String> = []
        var result: [String] = []

        for candidate in defaultSuggestions + availableTags {
            guard let tag = canonicalTag(candidate) else { continue }
            let identity = EventTitleMetadata.normalize(tag)
            guard !selected.contains(identity),
                  !excluded.contains(identity),
                  identities.insert(identity).inserted
            else { continue }
            result.append(tag)
        }
        return result
    }

    public static func canAdd(input: String, to selectedTags: [String]) -> Bool {
        canAdd(input: input, to: selectedTags, excludedTags: editorManagedTags)
    }

    public static func canAdd(
        input: String,
        to selectedTags: [String],
        excludedTags: [String]
    ) -> Bool {
        adding(input: input, to: selectedTags, excludedTags: excludedTags)
            != normalizedUnique(selectedTags)
    }

    public static func excludedTags(
        kind: ManagedCalendarItemKind,
        dateMode: CalendarDateMode
    ) -> [String] {
        var tags = ["タスク", "重要"]
        if kind == .task { tags.append("完了") }
        if dateMode == .estimatedWindow { tags.append("見込み") }
        return tags
    }

    public static func visibleTags(
        _ selectedTags: [String],
        excluding excludedTags: [String]
    ) -> [String] {
        let excluded = Set(excludedTags.map(EventTitleMetadata.normalize))
        return normalizedUnique(selectedTags).filter {
            !excluded.contains(EventTitleMetadata.normalize($0))
        }
    }

    public static func completionState(
        tags: [String],
        isCompleted: Bool,
        kind: ManagedCalendarItemKind
    ) -> CalendarTagCompletionState {
        var preservedTags = normalizedUnique(tags)
        let completionIdentity = EventTitleMetadata.normalize("完了")
        let hasCompletionTag = preservedTags.contains {
            EventTitleMetadata.normalize($0) == completionIdentity
        }

        switch kind {
        case .task:
            preservedTags.removeAll {
                EventTitleMetadata.normalize($0) == completionIdentity
            }
            return CalendarTagCompletionState(
                tags: preservedTags,
                isCompleted: isCompleted || hasCompletionTag
            )
        case .event:
            if isCompleted, !hasCompletionTag {
                preservedTags.append("完了")
            }
            return CalendarTagCompletionState(tags: preservedTags, isCompleted: false)
        }
    }

    private static func parsedTags(from input: String) -> [String] {
        input
            .split { character in
                character.isWhitespace || character == "," || character == "、"
            }
            .compactMap { canonicalTag(String($0)) }
    }

    private static func normalizedUnique(_ tags: [String]) -> [String] {
        var identities: Set<String> = []
        return tags.compactMap { candidate in
            guard let tag = canonicalTag(candidate) else { return nil }
            let identity = EventTitleMetadata.normalize(tag)
            return identities.insert(identity).inserted ? tag : nil
        }
    }

    private static func canonicalTag(_ candidate: String) -> String? {
        var value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.first == "#" || value.first == "＃" {
            value.removeFirst()
        }
        return EventTitleTagMutator.canonicalTag(value)
    }
}

public struct CalendarTagCompletionState: Equatable, Sendable {
    public let tags: [String]
    public let isCompleted: Bool

    public init(tags: [String], isCompleted: Bool) {
        self.tags = tags
        self.isCompleted = isCompleted
    }
}
