import SwiftUI

struct DateStrip: View {
    @ObservedObject var model: CalendarViewModel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                ForEach(model.dateChoices, id: \.self) { date in
                    DateChip(
                        date: date,
                        isSelected: Calendar.current.isDate(date, inSameDayAs: model.selectedDate),
                        isToday: Calendar.current.isDateInToday(date),
                        onSelect: { model.selectDate(date) }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("date-strip")
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
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Text(date.formatted(.dateTime.day()))
                    .font(.headline.monospacedDigit())
                Circle()
                    .fill(isToday ? Color.accentColor : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(width: 48, height: 66)
            .contentShape(.rect)
        }
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
