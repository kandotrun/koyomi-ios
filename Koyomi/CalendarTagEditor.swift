import SwiftUI

struct CalendarTagEditor: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selectedTags: [String]
    let availableTags: [String]
    let excludedTags: [String]
    let onInputCommitted: () -> Void

    @State private var input = ""
    @FocusState private var isInputFocused: Bool

    init(
        selectedTags: Binding<[String]>,
        availableTags: [String],
        excludedTags: [String],
        onInputCommitted: @escaping () -> Void = {}
    ) {
        _selectedTags = selectedTags
        self.availableTags = availableTags
        self.excludedTags = excludedTags
        self.onInputCommitted = onInputCommitted
    }

    private var suggestions: [String] {
        Array(
            CalendarTagEditorPolicy.suggestions(
                availableTags: availableTags,
                selectedTags: selectedTags,
                excludedTags: excludedTags
            )
            .prefix(10)
        )
    }

    private var visibleSelectedTags: [String] {
        CalendarTagEditorPolicy.visibleTags(selectedTags, excluding: excludedTags)
    }

    private var canAddInput: Bool {
        CalendarTagEditorPolicy.canAdd(
            input: input,
            to: selectedTags,
            excludedTags: excludedTags
        )
    }

    private var suggestionsPerPage: Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : 3
    }

    var body: some View {
        Section {
            if visibleSelectedTags.isEmpty {
                Label("タグなし", systemImage: "number")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("calendar-item-tags-empty")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("選択中")
                            .font(.caption.weight(.semibold))
                        Spacer(minLength: 8)
                        Text("タップで外す")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    CalendarTagFlowLayout(spacing: 6) {
                        ForEach(visibleSelectedTags, id: \.self) { tag in
                            selectedTagButton(tag)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("calendar-item-selected-tags")
            }

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("候補")
                        .font(.caption.weight(.semibold))

                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { tag in
                                suggestionButton(tag)
                                    .containerRelativeFrame(
                                        .horizontal,
                                        count: suggestionsPerPage,
                                        span: 1,
                                        spacing: 8
                                    )
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("calendar-item-tag-suggestions-scroll")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("calendar-item-tag-suggestions")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("新しいタグ")
                    .font(.caption.weight(.semibold))

                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "number")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isInputFocused ? Color.accentColor : .secondary)
                            .accessibilityHidden(true)

                        TextField("タグ名", text: $input)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($isInputFocused)
                            .onSubmit(addInput)
                            .accessibilityLabel("新しいタグ")
                            .accessibilityHint("タグ名を入力して追加します")
                            .accessibilityIdentifier("calendar-item-tag-input")
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(
                        Color.primary.opacity(isInputFocused ? 0.09 : 0.055),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                isInputFocused
                                    ? Color.accentColor.opacity(0.7)
                                    : Color.primary.opacity(0.1),
                                lineWidth: isInputFocused ? 1.5 : 1
                            )
                    }

                    addTagButton
                }
            }
        } header: {
            Text("タグ")
        } footer: {
            Text("空白・カンマ区切りで複数追加できます。種類と重要度は上の項目で設定します。")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar-item-tags")
    }

    @ViewBuilder
    private func selectedTagButton(_ tag: String) -> some View {
        Button {
            selectedTags = CalendarTagEditorPolicy.removing(tag, from: selectedTags)
        } label: {
            HStack(spacing: 6) {
                Text("#\(tag)")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .allowsTightening(true)
                Image(systemName: "xmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(
                EventTagStyle.tint(for: tag).opacity(0.16),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(EventTagStyle.tint(for: tag).opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityLabel("タグ、\(tag)を削除")
        .accessibilityValue("選択中")
        .accessibilityHint("ダブルタップで外します")
        .accessibilityAddTraits(.isSelected)
        .accessibilityIdentifier("calendar-item-tag-selected-\(tag)")
    }

    @ViewBuilder
    private func suggestionButton(_ tag: String) -> some View {
        Button {
            selectedTags = CalendarTagEditorPolicy.adding(
                input: tag,
                to: selectedTags,
                excludedTags: excludedTags
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(EventTagStyle.tint(for: tag))
                    .accessibilityHidden(true)
                Text("#\(tag)")
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .allowsTightening(true)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(Color.primary.opacity(0.055), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(EventTagStyle.tint(for: tag).opacity(0.28), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityLabel("タグ、\(tag)を追加")
        .accessibilityIdentifier("calendar-item-tag-suggestion-\(tag)")
    }

    @ViewBuilder
    private var addTagButton: some View {
        if canAddInput {
            addTagButtonBase
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
        } else {
            addTagButtonBase
                .buttonStyle(.glass)
                .foregroundStyle(.secondary)
                .disabled(true)
        }
    }

    private var addTagButtonBase: some View {
        Button(action: addInput) {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .frame(minWidth: 32, minHeight: 32)
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel("タグを追加")
        .accessibilityValue(canAddInput ? "追加できます" : "タグ名を入力")
        .accessibilityIdentifier("calendar-item-tag-add")
    }

    private func addInput() {
        guard canAddInput else { return }
        selectedTags = CalendarTagEditorPolicy.adding(
            input: input,
            to: selectedTags,
            excludedTags: excludedTags
        )
        input = ""
        isInputFocused = false
        onInputCommitted()
    }
}

private struct CalendarTagFlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let arrangement = arrange(
            proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
            subviews: subviews
        )
        for (index, point) in arrangement.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: ProposedViewSize(arrangement.sizes[index])
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> Arrangement {
        // The editor is iPhone-only. A bounded fallback also prevents a child
        // with a long unbroken tag from inflating Form's ideal width when its
        // first measurement arrives without an explicit proposal.
        let availableWidth = max(proposal.width ?? 320, 0)
        var points: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let proposedWidth = min(ideal.width, availableWidth)
            let fitted = subview.sizeThatFits(
                ProposedViewSize(width: proposedWidth, height: nil)
            )
            let size = CGSize(
                width: min(fitted.width, availableWidth),
                height: fitted.height
            )
            if x > 0, x + size.width > availableWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            sizes.append(size)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return Arrangement(
            points: points,
            sizes: sizes,
            size: CGSize(
                width: availableWidth,
                height: subviews.isEmpty ? 0 : y + rowHeight
            )
        )
    }

    private struct Arrangement {
        let points: [CGPoint]
        let sizes: [CGSize]
        let size: CGSize
    }
}
