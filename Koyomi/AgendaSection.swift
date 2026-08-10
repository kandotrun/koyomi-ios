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
                    .foregroundStyle(.primary.opacity(0.7))
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
                            onOpen: {
                                KoyomiHaptics.perform(.openEvent)
                                model.selectedEvent = event
                            },
                            onTogglePin: {
                                KoyomiHaptics.perform(.togglePin)
                                model.togglePin(event)
                            }
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

struct AgendaEventRow: View {
    let event: CalendarEvent
    let isPinned: Bool
    let onOpen: () -> Void
    let onTogglePin: () -> Void

    private var tint: Color { Color(koyomiHex: event.calendarColorHex) }
    private var metadata: EventTitleMetadata { event.titleMetadata }
    private var showsCalendarName: Bool { !metadata.containsTag(event.calendarName) }

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
                        .foregroundStyle(.primary.opacity(0.7))
                        .frame(width: 58, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(metadata.displayTitle)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        EventTagSummary(tags: metadata.tags)
                        if showsCalendarName || event.location != nil {
                            HStack(spacing: 6) {
                                if showsCalendarName {
                                    Text(event.calendarName)
                                }
                                if let location = event.location {
                                    Label(location, systemImage: "mappin")
                                        .labelStyle(.titleAndIcon)
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.primary.opacity(0.74))
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "pin.slash.fill" : "pin")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isPinned ? tint : Color.primary.opacity(0.74))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(
                isPinned
                    ? "\(metadata.displayTitle)のピン留めを解除"
                    : "\(metadata.displayTitle)をピン留め"
            )
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
        return event.startDate.formatted(
            .dateTime.hour().minute().locale(Locale(identifier: "ja_JP"))
        )
    }
}
