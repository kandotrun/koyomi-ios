import SwiftUI

struct DateStrip: View {
    @ObservedObject var model: CalendarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                model.selectedDate.formatted(
                    .dateTime.year().month(.wide).locale(Locale(identifier: "ja_JP"))
                )
            )
            .font(.headline)
            .padding(.horizontal, 20)
            .accessibilityIdentifier("month-title")

            HStack(spacing: 4) {
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
}

private struct DateChip: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 5) {
                Text(date.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "ja_JP"))))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.72))
                Text(date.formatted(.dateTime.day()))
                    .font(.headline.monospacedDigit())
                Circle()
                    .fill(isToday ? Color.accentColor : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
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
