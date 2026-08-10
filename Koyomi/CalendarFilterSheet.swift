import SwiftUI

struct CalendarFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: CalendarViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                KoyomiBackdrop()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        selectionSummary

                        if model.calendars.isEmpty {
                            ContentUnavailableView(
                                "カレンダーがありません",
                                systemImage: "calendar.badge.exclamationmark",
                                description: Text("iPhoneのカレンダー設定を確認してください。")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 44)
                        } else {
                            ForEach(sourceNames, id: \.self) { sourceName in
                                calendarGroup(sourceName)
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("表示するカレンダー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
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
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        KoyomiHaptics.perform(.dismiss)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(430), .large])
    }

    private var selectionSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: model.selectedCalendarIDs.isEmpty ? "eye.slash" : "eye")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(model.selectedCalendarIDs.count) / \(model.calendars.count)件を表示")
                    .font(.headline)
                Text(model.selectedCalendarIDs.isEmpty ? "予定はすべて非表示になります" : "選択はこのiPhoneに保存されます")
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.7))
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .accessibilityIdentifier("calendar-filter-summary")
    }

    private var sourceNames: [String] {
        Array(Set(model.calendars.map(\.sourceName))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    @ViewBuilder
    private func calendarGroup(_ sourceName: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sourceName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.68))
                .padding(.horizontal, 4)

            VStack(spacing: 1) {
                ForEach(model.calendars.filter { $0.sourceName == sourceName }) { calendar in
                    calendarButton(calendar)
                    if calendar.id != model.calendars.filter({ $0.sourceName == sourceName }).last?.id {
                        Divider().padding(.leading, 50)
                    }
                }
            }
            .padding(.horizontal, 14)
            .koyomiGlass(tint: .accentColor, cornerRadius: 24)
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
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? Color(koyomiHex: calendar.colorHex) : Color.secondary)
            }
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(calendar.title)、\(isSelected ? "表示中" : "非表示")")
        .accessibilityIdentifier("calendar-toggle-\(calendar.id)")
    }
}
