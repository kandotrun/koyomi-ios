import SwiftUI
import WidgetKit

private let widgetKind = "KoyomiPinnedCountdown"

struct KoyomiWidgetEntry: TimelineEntry {
    let date: Date
    let pins: [PinnedEvent]
}

struct KoyomiWidgetProvider: TimelineProvider {
    private let store = PinnedEventsStore()

    func placeholder(in context: Context) -> KoyomiWidgetEntry {
        KoyomiWidgetEntry(date: .now, pins: [Self.placeholderPin])
    }

    func getSnapshot(in context: Context, completion: @escaping (KoyomiWidgetEntry) -> Void) {
        let now = Date()
        let pins = WidgetPinSelector.activePins(from: store.load(), at: now, limit: 3)
        completion(KoyomiWidgetEntry(date: now, pins: pins.isEmpty && context.isPreview ? [Self.placeholderPin] : pins))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KoyomiWidgetEntry>) -> Void) {
        let now = Date()
        let allPins = store.load()
        let pins = WidgetPinSelector.activePins(from: allPins, at: now, limit: 3)
        let transitions = pins.flatMap { [$0.startDate, $0.endDate] }.filter { $0 > now }
        let nextRefresh = transitions.min()?.addingTimeInterval(2) ?? now.addingTimeInterval(6 * 3_600)
        completion(
            Timeline(
                entries: [KoyomiWidgetEntry(date: now, pins: pins)],
                policy: .after(nextRefresh)
            )
        )
    }

    private static var placeholderPin: PinnedEvent {
        let start = Date().addingTimeInterval(86_400 + 3_661)
        return PinnedEvent(
            id: "placeholder",
            eventIdentifier: "placeholder",
            externalIdentifier: nil,
            title: "大切な予定",
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            isAllDay: false,
            calendarName: "カレンダー",
            calendarColorHex: "5B8DEF",
            location: nil
        )
    }
}

struct KoyomiWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KoyomiWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumContent
            case .accessoryRectangular:
                accessoryContent
            default:
                smallContent
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryRectangular {
                Color.clear
            } else {
                LinearGradient(
                    colors: [Color(koyomiHex: "10213D"), Color(koyomiHex: "1B3154")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    @ViewBuilder
    private var smallContent: some View {
        if let pin = entry.pins.first {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(Color(koyomiHex: pin.calendarColorHex))
                    Text(pin.calendarName)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                Text(pin.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 2)
                countdown(for: pin, large: true)
            }
            .foregroundStyle(.white)
            .widgetURL(deepLink(for: pin))
        } else {
            emptyContent
        }
    }

    @ViewBuilder
    private var mediumContent: some View {
        if entry.pins.isEmpty {
            emptyContent
        } else {
            VStack(alignment: .leading, spacing: 9) {
                Label("ピン留め", systemImage: "pin.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))
                ForEach(entry.pins.prefix(3)) { pin in
                    Link(destination: deepLink(for: pin)) {
                        HStack(spacing: 10) {
                            Capsule()
                                .fill(Color(koyomiHex: pin.calendarColorHex))
                                .frame(width: 4, height: 31)
                            Text(pin.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            countdown(for: pin, large: false)
                        }
                    }
                }
            }
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var accessoryContent: some View {
        if let pin = entry.pins.first {
            VStack(alignment: .leading, spacing: 2) {
                Text(pin.title)
                    .font(.headline)
                    .lineLimit(1)
                countdown(for: pin, large: false)
            }
            .widgetURL(deepLink(for: pin))
        } else {
            Label("ピン留めなし", systemImage: "pin")
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "pin")
                .font(.title2)
            Text("予定をピン留め")
                .font(.headline)
            Text("こよみを開いて、大切な予定を選んでください。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    private func countdown(for pin: PinnedEvent, large: Bool) -> some View {
        let isUpcoming = entry.date < pin.startDate
        let target = isUpcoming ? pin.startDate : pin.endDate
        return VStack(alignment: .leading, spacing: 1) {
            Text(isUpcoming ? "あと" : "終了まで")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(target, style: .timer)
                .font(large ? .title3.bold().monospacedDigit() : .caption.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func deepLink(for pin: PinnedEvent) -> URL {
        let id = pin.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pin.id
        return URL(string: "koyomi://event/\(id)")!
    }
}

struct KoyomiPinnedCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind, provider: KoyomiWidgetProvider()) { entry in
            KoyomiWidgetView(entry: entry)
        }
        .configurationDisplayName("ピン留めカウントダウン")
        .description("大切な予定までの時間を、いつでも確認できます。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

@main
struct KoyomiWidgetBundle: WidgetBundle {
    var body: some Widget {
        KoyomiPinnedCountdownWidget()
    }
}
