import SwiftUI

struct EventTagFilterBar: View {
    @ObservedObject var model: CalendarViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    EventTagFilterButton(
                        title: "すべて",
                        tag: nil,
                        isSelected: model.selectedTag == nil,
                        action: { select(nil) }
                    )

                    ForEach(model.availableTags, id: \.self) { tag in
                        EventTagFilterButton(
                            title: "#\(tag)",
                            tag: tag,
                            isSelected: EventTagStyle.matches(model.selectedTag, tag),
                            action: { select(tag) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("event-tag-filter")
    }

    private func select(_ tag: String?) {
        KoyomiHaptics.perform(.switchAgenda)
        if EventTagAnimationPolicy.shouldAnimate(reduceMotionEnabled: reduceMotion) {
            withAnimation(.snappy) {
                model.selectTag(tag)
            }
        } else {
            model.selectTag(tag)
        }
    }
}

struct EventTagSummary: View {
    let tags: [String]
    var limit = 2

    var body: some View {
        if !tags.isEmpty {
            ViewThatFits(in: .horizontal) {
                EventTagRow(
                    tags: Array(tags.prefix(limit)),
                    hiddenCount: max(tags.count - limit, 0),
                    preservesIntrinsicTagWidth: true
                )
                EventTagColumn(
                    tags: Array(tags.prefix(limit)),
                    hiddenCount: max(tags.count - limit, 0)
                )
            }
        }
    }
}

private struct EventTagColumn: View {
    let tags: [String]
    let hiddenCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 6) {
                    EventTagChip(tag: tag, preservesIntrinsicWidth: false)

                    if tag == tags.last, hiddenCount > 0 {
                        EventTagOverflowCount(count: hiddenCount)
                    }
                }
            }
        }
    }
}

private struct EventTagRow: View {
    let tags: [String]
    let hiddenCount: Int
    let preservesIntrinsicTagWidth: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                EventTagChip(
                    tag: tag,
                    preservesIntrinsicWidth: preservesIntrinsicTagWidth
                )
            }

            if hiddenCount > 0 {
                EventTagOverflowCount(count: hiddenCount)
            }
        }
    }
}

private struct EventTagOverflowCount: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("他に\(count)個のタグ")
    }
}

private struct EventTagChip: View {
    let tag: String
    let preservesIntrinsicWidth: Bool

    var body: some View {
        if preservesIntrinsicWidth {
            chip
                .fixedSize(horizontal: true, vertical: false)
        } else {
            chip
        }
    }

    private var chip: some View {
        Text("#\(tag)")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(EventTagStyle.tint(for: tag))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(EventTagStyle.tint(for: tag).opacity(0.24), lineWidth: 0.5)
            }
            .accessibilityLabel("タグ、\(tag)")
            .accessibilityIdentifier("event-tag-chip-\(tag)")
    }
}

private struct EventTagFilterButton: View {
    let title: String
    let tag: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            button
                .buttonStyle(.glassProminent)
                .tint(tag.map(EventTagStyle.tint(for:)) ?? .accentColor)
        } else {
            button
                .buttonStyle(.glass)
                .tint(tag.map(EventTagStyle.tint(for:)) ?? .accentColor)
        }
    }

    private var button: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 2)
        }
        .accessibilityLabel(tag.map { "タグ、\($0)で絞り込む" } ?? "すべての予定を表示")
        .accessibilityValue(isSelected ? "選択中" : "")
        .accessibilityIdentifier(tag.map { "event-tag-filter-\($0)" } ?? "event-tag-filter-all")
    }
}

enum EventTagStyle {
    private static let palette = [
        Color(koyomiHex: "5B8DEF"),
        Color(koyomiHex: "6B9B55"),
        Color(koyomiHex: "A56CC1"),
        Color(koyomiHex: "D17A45"),
        Color(koyomiHex: "2A9D8F"),
    ]

    static func tint(for tag: String) -> Color {
        switch EventTitleMetadata.normalize(tag) {
        case EventTitleMetadata.normalize("重要"):
            return .red
        case EventTitleMetadata.normalize("タスク"):
            return .orange
        case EventTitleMetadata.normalize("仕事"):
            return Color(koyomiHex: "5B8DEF")
        case EventTitleMetadata.normalize("メモ"):
            return .purple
        default:
            let index = EventTagIndex.stablePaletteIndex(for: tag, paletteCount: palette.count)
            return palette[index]
        }
    }

    static func matches(_ lhs: String?, _ rhs: String) -> Bool {
        guard let lhs else { return false }
        return EventTitleMetadata.normalize(lhs) == EventTitleMetadata.normalize(rhs)
    }
}
