import SwiftUI

struct AgendaSection: View {
    @ObservedObject var model: CalendarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.selectedDateTitle)
                    .font(.title2.bold())
                Spacer()
                Text(model.agendaEvents.isEmpty ? "予定なし" : "\(model.agendaEvents.count)件")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)

            VStack(spacing: 10) {
                if model.agendaEvents.isEmpty {
                    ContentUnavailableView(
                        "予定はありません",
                        systemImage: "calendar",
                        description: Text("別の日を選ぶか、下に引いて更新してください。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 34)
                } else {
                    ForEach(model.agendaEvents) { event in
                        AgendaEventRow(
                            event: event,
                            isPinned: model.isPinned(event),
                            onOpen: { model.selectedEvent = event },
                            onTogglePin: { model.togglePin(event) }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("agenda-list")
        }
        .padding(.bottom, 28)
    }
}

private struct AgendaEventRow: View {
    let event: CalendarEvent
    let isPinned: Bool
    let onOpen: () -> Void
    let onTogglePin: () -> Void

    private var tint: Color { Color(koyomiHex: event.calendarColorHex) }

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tint)
                .frame(width: 5)
                .accessibilityHidden(true)

            Button(action: onOpen) {
                HStack(spacing: 14) {
                    Text(timeText)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(event.calendarName)
                            if let location = event.location {
                                Text("•")
                                Text(location)
                                    .lineLimit(1)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isPinned ? tint : .secondary)
                    .frame(width: 38, height: 38)
            }
            .accessibilityLabel(isPinned ? "\(event.title)のピン留めを解除" : "\(event.title)をピン留め")
        }
        .padding(14)
        .frame(minHeight: 78)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
    }

    private var timeText: String {
        if event.isAllDay { return "終日" }
        return event.startDate.formatted(date: .omitted, time: .shortened)
    }
}
