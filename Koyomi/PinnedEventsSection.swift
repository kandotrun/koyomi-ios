import SwiftUI

enum KoyomiPinnedTimeline {
    static func visiblePins(from pins: [PinnedEvent], at date: Date) -> [PinnedEvent] {
        WidgetPinSelector.activePins(from: pins, at: date, limit: pins.count)
    }

    static func nextBoundary(in pins: [PinnedEvent], after date: Date) -> Date? {
        pins.flatMap { [$0.startDate, $0.endDate] }
            .filter { $0 > date }
            .min()
    }
}

struct PinnedEventsSection: View {
    @ObservedObject var model: CalendarViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isExpanded = false
    @State private var pinReferenceDate = Date()

    private var displayedPins: [PinnedEvent] {
        KoyomiPinnedTimeline.visiblePins(from: model.pinnedEvents, at: pinReferenceDate)
    }

    private var nextBoundary: Date? {
        KoyomiPinnedTimeline.nextBoundary(in: model.pinnedEvents, after: pinReferenceDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader

            if displayedPins.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "pin")
                        .foregroundStyle(.secondary)
                    Text("大切な予定をピン留めすると、ここでカウントできます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 20)
            } else if isExpanded {
                expandedPins
            } else if let pin = displayedPins.first {
                PinnedSummaryRow(
                    pin: pin,
                    onOpen: {
                        KoyomiHaptics.perform(.openEvent)
                        model.selectedEvent = model.event(for: pin)
                    }
                )
                .padding(.horizontal, 20)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pinned-section")
        .task(id: nextBoundary) {
            guard let nextBoundary else { return }
            let delay = nextBoundary.timeIntervalSinceNow
            if delay > 0 {
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
            }
            pinReferenceDate = .now
        }
        .onAppear {
            pinReferenceDate = .now
        }
        .onChange(of: model.pinnedEvents) { _, _ in
            pinReferenceDate = .now
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                pinReferenceDate = .now
            }
        }
    }

    @ViewBuilder
    private var sectionHeader: some View {
        if displayedPins.isEmpty {
            HStack {
                Label("ピン留め", systemImage: "pin.fill")
                    .font(.headline)
                Spacer()
                Text("0件")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
        } else {
            Button {
                KoyomiHaptics.perform(.switchAgenda)
                if reduceMotion {
                    isExpanded.toggle()
                } else {
                    withAnimation(.snappy) { isExpanded.toggle() }
                }
            } label: {
                HStack(spacing: 8) {
                    Label("ピン留め", systemImage: "pin.fill")
                        .font(.headline)
                    Spacer()
                    Text("\(displayedPins.count)件")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .accessibilityLabel("ピン留め、\(displayedPins.count)件")
            .accessibilityValue(isExpanded ? "展開中" : "折りたたみ中")
            .accessibilityHint(isExpanded ? "ダブルタップして折りたたむ" : "ダブルタップしてすべて表示")
            .accessibilityIdentifier("pinned-section-toggle")
        }
    }

    private var expandedPins: some View {
        GlassEffectContainer(spacing: 18) {
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(displayedPins) { pin in
                        PinnedCountdownCard(
                            pin: pin,
                            onOpen: {
                                KoyomiHaptics.perform(.openEvent)
                                model.selectedEvent = model.event(for: pin)
                            },
                            onRemove: {
                                KoyomiHaptics.perform(.togglePin)
                                model.removePin(pin)
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("pinned-cards-scroll")
        }
    }
}

private struct PinnedSummaryRow: View {
    let pin: PinnedEvent
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var tint: Color { Color(koyomiHex: pin.calendarColorHex) }
    private var metadata: EventTitleMetadata { pin.titleMetadata }
    private var refreshInterval: TimeInterval { pin.isEstimatedDateWindow ? 3_600 : 60 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: refreshInterval)) { context in
            let countdown = CountdownCalculator.compactText(for: pin, now: context.date)
            Button(action: onOpen) {
                summaryContent(countdown: countdown)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityLabel("\(metadata.displayTitle)、\(countdown)、\(pin.koyomiDateText)")
            .accessibilityHint("ダブルタップして詳細を開く")
            .accessibilityIdentifier("pin-summary-\(pin.id)")
        }
    }

    @ViewBuilder
    private func summaryContent(countdown: String) -> some View {
        if KoyomiResponsiveLayout.usesVerticalCardLayout(for: dynamicTypeSize) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint)
                        .frame(width: 4)
                        .frame(maxHeight: .infinity)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(metadata.displayTitle)
                            .font(.body.weight(.semibold))
                            .strikethrough(metadata.containsTag("タスク") && metadata.containsTag("完了"))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(pin.koyomiDateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                countdownText(countdown)
            }
        } else {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint)
                    .frame(width: 4, height: 46)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata.displayTitle)
                        .font(.body.weight(.semibold))
                        .strikethrough(metadata.containsTag("タスク") && metadata.containsTag("完了"))
                        .lineLimit(1)
                    Text(pin.koyomiDateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                countdownText(countdown)
            }
        }
    }

    private func countdownText(_ countdown: String) -> some View {
        Text(countdown)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
    }
}

private struct PinnedCountdownCard: View {
    let pin: PinnedEvent
    let onOpen: () -> Void
    let onRemove: () -> Void

    private var tint: Color { Color(koyomiHex: pin.calendarColorHex) }
    private var metadata: EventTitleMetadata { pin.titleMetadata }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if pin.isEstimatedDateWindow {
                TimelineView(.periodic(from: .now, by: 3_600)) { context in
                    card(at: context.date)
                }
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    card(at: context.date)
                }
            }

            Button(action: onRemove) {
                Image(systemName: "pin.slash.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .padding(.top, 10)
            .padding(.trailing, 10)
            .accessibilityLabel("\(metadata.displayTitle)のピン留めを解除")
            .accessibilityIdentifier("pin-remove-\(pin.id)")
        }
    }

    private func card(at date: Date) -> some View {
        let presentation = CountdownCalculator.presentation(for: pin, now: date)
        return Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        if !metadata.containsTag(pin.calendarName) {
                            Text(pin.calendarName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary.opacity(0.68))
                        }
                        Text(metadata.displayTitle)
                            .font(.title3.bold())
                            .strikethrough(metadata.containsTag("タスク") && metadata.containsTag("完了"))
                            .foregroundStyle(
                                metadata.containsTag("タスク") && metadata.containsTag("完了")
                                    ? .secondary
                                    : .primary
                            )
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        EventTagSummary(tags: metadata.tags)
                    }
                    Spacer(minLength: 44)
                }

                countdown(presentation)

                HStack(spacing: 8) {
                    Image(
                        systemName: pin.isEstimatedDateWindow
                            ? "calendar.badge.clock"
                            : (pin.isAllDay ? "sun.max" : "clock")
                    )
                    Text(pin.koyomiDateText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.68))
            }
            .padding(16)
            .frame(width: 306, alignment: .topLeading)
            .frame(minHeight: metadata.tags.isEmpty ? 162 : 178, alignment: .topLeading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .koyomiGlass(tint: tint, cornerRadius: 24, interactive: true)
        .accessibilityLabel(
            "\(metadata.displayTitle)、\(pin.calendarName)、\(pin.koyomiDateText)、\(presentation.label) \(presentation.value)"
        )
        .accessibilityHint("ダブルタップして詳細を開く")
        .accessibilityIdentifier("pin-card-\(pin.id)")
    }

    private func countdown(_ presentation: CountdownPresentation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(presentation.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.68))
            Text(presentation.value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityHidden(true)
        }
    }
}

private extension PinnedEvent {
    var koyomiDateText: String {
        if let window = CalendarEstimatedWindow(event: self) {
            let start = window.startDate.formatted(
                .dateTime.month(.abbreviated).day().locale(Locale(identifier: "ja_JP"))
            )
            let latest = window.latestDate.formatted(
                .dateTime.month(.abbreviated).day().locale(Locale(identifier: "ja_JP"))
            )
            return "見込み期間 \(start)〜\(latest)"
        }
        if isAllDay {
            return startDate.formatted(
                .dateTime.month(.abbreviated).day().weekday(.short).locale(Locale(identifier: "ja_JP"))
            )
        }
        return startDate.formatted(
            .dateTime.month(.abbreviated).day().weekday(.short).hour().minute().locale(Locale(identifier: "ja_JP"))
        )
    }
}
