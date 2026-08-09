import SwiftUI

struct EventDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let event: CalendarEvent
    let isPinned: Bool
    let onTogglePin: () -> Void

    private var tint: Color { Color(koyomiHex: event.calendarColorHex) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "calendar")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(tint)
                                .frame(width: 52, height: 52)
                                .koyomiGlass(tint: tint, cornerRadius: 18)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(event.calendarName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(event.title)
                                    .font(.title2.bold())
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Divider()

                        DetailLine(symbol: "clock", title: "日時", value: dateText, tint: tint)
                        if let location = event.location {
                            DetailLine(symbol: "mappin.and.ellipse", title: "場所", value: location, tint: tint)
                        }
                    }
                    .padding(22)
                    .koyomiGlass(tint: tint, cornerRadius: 30)

                    Button {
                        onTogglePin()
                        dismiss()
                    } label: {
                        Label(
                            isPinned ? "ピン留めを解除" : "この予定をピン留め",
                            systemImage: isPinned ? "pin.slash.fill" : "pin.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(tint)
                }
                .padding(20)
            }
            .background(KoyomiBackdrop())
            .navigationTitle("予定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private var dateText: String {
        if event.isAllDay {
            return "\(event.startDate.formatted(.dateTime.year().month(.wide).day().weekday(.wide).locale(Locale(identifier: "ja_JP"))))・終日"
        }
        let start = event.startDate.formatted(
            .dateTime.year().month(.wide).day().weekday(.wide).hour().minute().locale(Locale(identifier: "ja_JP"))
        )
        let end = event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start)〜\(end)"
    }
}

private struct DetailLine: View {
    let symbol: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
