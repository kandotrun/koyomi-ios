import SwiftUI

struct PinnedEventsSection: View {
    @ObservedObject var model: CalendarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("ピン留め", systemImage: "pin.fill")
                    .font(.headline)
                Spacer()
                if !model.pinnedEvents.isEmpty {
                    Text("\(model.pinnedEvents.count)件")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)

            if model.displayedPins.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "pin")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("大切な予定をピン留めすると、ここでカウントできます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .koyomiGlass(tint: Color(koyomiHex: "5B8DEF"), cornerRadius: 24)
                .padding(.horizontal, 20)
            } else {
                GlassEffectContainer(spacing: 18) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 14) {
                            ForEach(model.displayedPins) { pin in
                                PinnedCountdownCard(
                                    pin: pin,
                                    onOpen: { model.selectedEvent = model.event(for: pin) },
                                    onRemove: { model.removePin(pin) }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pinned-section")
    }
}

private struct PinnedCountdownCard: View {
    let pin: PinnedEvent
    let onOpen: () -> Void
    let onRemove: () -> Void

    private var tint: Color { Color(koyomiHex: pin.calendarColorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(pin.calendarName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.68))
                    Text(pin.title)
                        .font(.title3.bold())
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Button(action: onRemove) {
                    Image(systemName: "pin.slash.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("\(pin.title)のピン留めを解除")
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let presentation = CountdownCalculator.presentation(for: pin, now: context.date)
                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.68))
                    Text(presentation.value)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityLabel("\(presentation.label) \(presentation.value)")
                }
            }

            HStack(spacing: 8) {
                Image(systemName: pin.isAllDay ? "sun.max" : "clock")
                Text(dateText)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.primary.opacity(0.68))
        }
        .padding(18)
        .frame(width: 330, alignment: .topLeading)
        .frame(minHeight: 174, alignment: .topLeading)
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
        .koyomiGlass(tint: tint, cornerRadius: 28, interactive: true)
        .accessibilityIdentifier("pin-card-\(pin.id)")
    }

    private var dateText: String {
        if pin.isAllDay {
            return pin.startDate.formatted(
                .dateTime.month(.abbreviated).day().weekday(.short).locale(Locale(identifier: "ja_JP"))
            )
        }
        return pin.startDate.formatted(
            .dateTime.month(.abbreviated).day().weekday(.short).hour().minute().locale(Locale(identifier: "ja_JP"))
        )
    }
}
