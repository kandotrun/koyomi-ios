import SwiftUI

struct AgendaSection: View {
    @ObservedObject var model: CalendarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.selectedDateTitle)
                    .font(.title3.bold())
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
                                model.togglePin(event, scope: $0)
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
    let onTogglePin: (CalendarMutationScope) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isPinScopePresented = false

    private var tint: Color { Color(koyomiHex: event.calendarColorHex) }
    private var metadata: EventTitleMetadata { event.titleMetadata }
    private var showsCalendarName: Bool { !metadata.containsTag(event.calendarName) }
    private var visibleTags: [String] {
        metadata.tags.filter {
            !(event.isEstimatedDateWindow
                && EventTitleMetadata.normalize($0) == EventTitleMetadata.normalize("見込み"))
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tint)
                .frame(width: 5)
                .accessibilityHidden(true)

            Button(action: onOpen) {
                eventContent
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("agenda-event-\(event.eventIdentifier)")

            if event.canEdit {
                Button(action: requestPinChange) {
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
                .accessibilityIdentifier("agenda-pin-\(event.eventIdentifier)")
            }
        }
        .padding(12)
        .frame(minHeight: 72)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .confirmationDialog(
            "ピン留めを変更する範囲",
            isPresented: $isPinScopePresented,
            titleVisibility: .visible
        ) {
            Button("この予定のみ") { onTogglePin(.thisEvent) }
            Button("これ以降すべて") { onTogglePin(.futureEvents) }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private func requestPinChange() {
        if event.isRecurring {
            isPinScopePresented = true
        } else {
            onTogglePin(.thisEvent)
        }
    }

    @ViewBuilder
    private var eventContent: some View {
        if KoyomiResponsiveLayout.usesVerticalCardLayout(for: dynamicTypeSize) {
            VStack(alignment: .leading, spacing: 8) {
                timeLabel
                eventDetails
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 12) {
                timeLabel
                    .frame(width: 52, alignment: .leading)
                eventDetails
                Spacer(minLength: 4)
            }
        }
    }

    private var timeLabel: some View {
        Text(timeText)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.primary.opacity(0.7))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var eventDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metadata.displayTitle)
                .font(.body.weight(.semibold))
                .strikethrough(event.isCompletedTask)
                .foregroundStyle(event.isCompletedTask ? .secondary : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            EventTagSummary(tags: visibleTags)
            if let estimatedStatusText {
                Label(estimatedStatusText, systemImage: "calendar.badge.clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
            }
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
                .font(.caption2)
                .foregroundStyle(.primary.opacity(0.74))
            }
        }
    }

    private var estimatedStatusText: String? {
        guard let window = CalendarEstimatedWindow(event: event) else { return nil }
        if event.isCompletedTask { return "完了済み" }
        return switch window.status(at: .now) {
        case let .upcoming(daysUntilStart):
            "あと\(daysUntilStart)日"
        case let .withinWindow(daysUntilLatest):
            "遅くとも\(daysUntilLatest)日"
        case let .overdue(days):
            "\(days)日超過"
        }
    }

    private var timeText: String {
        if event.isEstimatedDateWindow { return "見込み" }
        if event.isAllDay { return "終日" }
        return event.startDate.formatted(
            .dateTime.hour().minute().locale(Locale(identifier: "ja_JP"))
        )
    }
}
