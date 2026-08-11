import SwiftUI

struct UpcomingEventsSection: View {
    @ObservedObject var model: CalendarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("これから")
                        .font(.title2.bold())
                    Text("18か月先＋未完了の見込み")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(upcomingEventCount == 0 ? "予定なし" : "\(upcomingEventCount)件")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.7))
            }
            .padding(.horizontal, 20)

            if model.upcomingSections.isEmpty {
                ContentUnavailableView(
                    "今後の予定はありません",
                    systemImage: "calendar.badge.checkmark",
                    description: Text(model.selectedCalendarIDs.isEmpty
                        ? "表示するカレンダーを選択してください。"
                        : "新しい予定が追加されたら、ここに日付順で表示されます。")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .padding(.horizontal, 20)
            } else {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(model.upcomingSections) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(dateTitle(section.day))
                                .font(.headline)
                                .padding(.horizontal, 4)

                            VStack(spacing: 10) {
                                ForEach(section.events) { event in
                                    AgendaEventRow(
                                        event: event,
                                        isPinned: model.isPinned(event),
                                        onOpen: {
                                            KoyomiHaptics.perform(.openEvent)
                                            model.selectedEvent = event
                                        },
                                        onTogglePin: {
                                            KoyomiHaptics.perform(.togglePin)
                                            model.togglePin(event)
                                        }
                                    )
                                    .accessibilityIdentifier("upcoming-event-\(event.eventIdentifier)")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("upcoming-list")
            }
        }
        .padding(.bottom, 28)
    }

    private var upcomingEventCount: Int {
        model.upcomingSections.reduce(0) { $0 + $1.events.count }
    }

    private func dateTitle(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = .current

        let components = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let currentYear = calendar.component(.year, from: Date())
        let weekdayIndex = max(0, min((components.weekday ?? 1) - 1, calendar.shortWeekdaySymbols.count - 1))
        let weekday = calendar.shortWeekdaySymbols[weekdayIndex]
        let monthAndDay = "\(components.month ?? 0)月\(components.day ?? 0)日（\(weekday)）"
        let formatted = components.year == currentYear
            ? monthAndDay
            : "\(components.year ?? 0)年\(monthAndDay)"

        if calendar.isDateInToday(date) { return "今日・\(formatted)" }
        if calendar.isDateInTomorrow(date) { return "明日・\(formatted)" }
        return formatted
    }
}
