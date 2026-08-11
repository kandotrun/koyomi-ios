import SwiftUI

enum KoyomiResponsiveLayout {
    static func usesVerticalCardLayout(for dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }
}

struct DateStrip: View {
    @ObservedObject var model: CalendarViewModel
    let onOpenCalendar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button(action: onOpenCalendar) {
                    HStack(spacing: 5) {
                        Text(monthTitle)
                        .accessibilityIdentifier("month-title")
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("日付を選ぶ、\(monthTitle)")
                .accessibilityHint("ダブルタップしてカレンダーを開く")
                .accessibilityIdentifier("open-date-picker")

                Spacer()

                if !Calendar.current.isDateInToday(model.selectedDate) {
                    Button {
                        KoyomiHaptics.perform(.selectDate)
                        model.selectToday()
                    } label: {
                        Text("今日")
                            .font(.subheadline.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("今日へ移動")
                }
            }
            .padding(.horizontal, 20)

            HStack(spacing: 2) {
                ForEach(model.dateChoices, id: \.self) { date in
                    DateChip(
                        date: date,
                        isSelected: Calendar.current.isDate(date, inSameDayAs: model.selectedDate),
                        isToday: Calendar.current.isDateInToday(date),
                        onSelect: {
                            KoyomiHaptics.perform(.selectDate)
                            model.selectDate(date)
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("date-strip")
        }
    }

    private var monthTitle: String {
        model.selectedDate.formatted(
            .dateTime.year().month(.wide).locale(Locale(identifier: "ja_JP"))
        )
    }
}

private struct DateChip: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let onSelect: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 5) {
                Text(date.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "ja_JP"))))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(date.formatted(.dateTime.day()))
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(
                        KoyomiResponsiveLayout.usesVerticalCardLayout(for: dynamicTypeSize) ? 0.6 : 0.85
                    )
                    .allowsTightening(true)
                Circle()
                    .fill(isToday ? Color.accentColor : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .contentShape(.rect)
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
        .modifier(SelectedDateGlass(isSelected: isSelected))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        let text = date.formatted(
            .dateTime.month(.wide).day().weekday(.wide).locale(Locale(identifier: "ja_JP"))
        )
        return isToday ? "今日、\(text)" : text
    }
}

private struct SelectedDateGlass: ViewModifier {
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content.koyomiGlass(tint: .accentColor, cornerRadius: 18, interactive: true)
        } else {
            content
        }
    }
}
