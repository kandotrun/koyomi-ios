import SwiftUI

struct CalendarFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: CalendarViewModel
    @Binding var displayMode: CalendarDisplayMode

    var body: some View {
        NavigationStack {
            ZStack {
                KoyomiBackdrop()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        displayModeGroup
                        itemFilterGroup
                        tagFilterGroup
                        calendarFilterGroup
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("表示と絞り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        KoyomiHaptics.perform(.dismiss)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var displayModeGroup: some View {
        optionGroup(title: "表示") {
            Picker("予定の表示", selection: $displayMode) {
                ForEach(CalendarDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: displayMode) { _, _ in
                KoyomiHaptics.perform(.switchAgenda)
            }
            .accessibilityIdentifier("calendar-display-mode")
        }
    }

    private var itemFilterGroup: some View {
        optionGroup(title: "状態") {
            VStack(spacing: 0) {
                ForEach(CalendarItemFilter.allCases) { filter in
                    selectionButton(
                        title: filter.title,
                        isSelected: model.itemFilter == filter,
                        identifier: "item-filter-\(filter.rawValue)"
                    ) {
                        KoyomiHaptics.perform(.switchAgenda)
                        model.selectItemFilter(filter)
                    }
                    if filter != CalendarItemFilter.allCases.last {
                        Divider().padding(.leading, 8)
                    }
                }
            }
        }
    }

    private var tagFilterGroup: some View {
        optionGroup(title: "タグ") {
            VStack(spacing: 0) {
                selectionButton(
                    title: "すべて",
                    isSelected: model.selectedTag == nil,
                    identifier: "event-tag-filter-all"
                ) {
                    KoyomiHaptics.perform(.switchAgenda)
                    model.selectTag(nil)
                }

                if model.availableTags.isEmpty {
                    Divider().padding(.leading, 8)
                    Text("タグは予定・タスクの追加／編集画面から設定できます")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 4)
                } else {
                    ForEach(model.availableTags, id: \.self) { tag in
                        Divider().padding(.leading, 8)
                        selectionButton(
                            title: "#\(tag)",
                            isSelected: EventTagStyle.matches(model.selectedTag, tag),
                            identifier: "event-tag-filter-\(tag)"
                        ) {
                            KoyomiHaptics.perform(.switchAgenda)
                            model.selectTag(tag)
                        }
                    }
                }
            }
        }
    }

    private var calendarFilterGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("カレンダー")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("すべて表示", systemImage: "checkmark.circle") {
                        KoyomiHaptics.perform(.changeCalendarFilter)
                        model.selectAllCalendars()
                    }
                    Button("すべて非表示", systemImage: "circle") {
                        KoyomiHaptics.perform(.changeCalendarFilter)
                        model.deselectAllCalendars()
                    }
                } label: {
                    Label("一括選択", systemImage: "ellipsis.circle")
                        .font(.subheadline.weight(.semibold))
                }
            }

            selectionSummary

            if model.calendars.isEmpty {
                ContentUnavailableView(
                    "カレンダーがありません",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("iPhoneのカレンダー設定を確認してください。")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ForEach(sourceNames, id: \.self) { sourceName in
                    calendarGroup(sourceName)
                }
            }
        }
    }

    private var selectionSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: model.selectedCalendarIDs.isEmpty ? "eye.slash" : "eye")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.selectedCalendarIDs.count) / \(model.calendars.count)件を表示")
                    .font(.subheadline.weight(.semibold))
                Text(model.selectedCalendarIDs.isEmpty ? "予定はすべて非表示になります" : "選択はこのiPhoneに保存されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("calendar-filter-summary")
    }

    private var sourceNames: [String] {
        Array(Set(model.calendars.map(\.sourceName))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private func optionGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func selectionButton(
        title: String,
        isSelected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "選択中" : "未選択")
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func calendarGroup(_ sourceName: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sourceName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                let calendars = model.calendars.filter { $0.sourceName == sourceName }
                ForEach(calendars) { calendar in
                    calendarButton(calendar)
                    if calendar.id != calendars.last?.id {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func calendarButton(_ calendar: CalendarDescriptor) -> some View {
        let isSelected = model.isCalendarSelected(calendar.id)
        return Button {
            KoyomiHaptics.perform(.changeCalendarFilter)
            model.toggleCalendar(calendar.id)
        } label: {
            HStack(spacing: 13) {
                Circle()
                    .fill(Color(koyomiHex: calendar.colorHex))
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)

                Text(calendar.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected ? Color(koyomiHex: calendar.colorHex) : Color.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(calendar.title)、\(isSelected ? "表示中" : "非表示")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? "選択中" : "未選択")
        .accessibilityIdentifier("calendar-toggle-\(calendar.id)")
    }
}
