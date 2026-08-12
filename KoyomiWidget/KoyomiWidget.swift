import SwiftUI
import WidgetKit

private let widgetKind = "KoyomiPinnedCountdown"

struct KoyomiWidgetEntry: TimelineEntry {
    let date: Date
    let pins: [PinnedEvent]
    let totalActivePinCount: Int
}

struct KoyomiWidgetProvider: TimelineProvider {
    private let store = PinnedEventsStore(storage: KeychainPinnedEventsDataStorage())

    func placeholder(in context: Context) -> KoyomiWidgetEntry {
        KoyomiWidgetEntry(date: .now, pins: [Self.placeholderPin], totalActivePinCount: 1)
    }

    func getSnapshot(in context: Context, completion: @escaping (KoyomiWidgetEntry) -> Void) {
        let now = Date()
        let allPins = store.load()
        let timelinePins = PinnedRecurrenceExpander.expandedPins(from: allPins, at: now)
        let pins = WidgetPinSelector.activePins(
            from: timelinePins,
            at: now,
            limit: pinLimit(for: context.family)
        )
        let usesPlaceholder = pins.isEmpty && context.isPreview
        completion(
            KoyomiWidgetEntry(
                date: now,
                pins: usesPlaceholder ? [Self.placeholderPin] : pins,
                totalActivePinCount: usesPlaceholder
                    ? 1
                    : WidgetPinSelector.activePinCount(from: timelinePins, at: now)
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KoyomiWidgetEntry>) -> Void) {
        let now = Date()
        let allPins = store.load()
        let timelinePins = PinnedRecurrenceExpander.expandedPins(from: allPins, at: now)
        let states = WidgetTimelinePlanner.states(
            from: timelinePins,
            at: now,
            limit: pinLimit(for: context.family)
        )
        let entries = states.map {
            KoyomiWidgetEntry(
                date: $0.date,
                pins: $0.pins,
                totalActivePinCount: WidgetPinSelector.activePinCount(
                    from: timelinePins,
                    at: $0.date
                )
            )
        }
        let policy: TimelineReloadPolicy = entries.count == 1
            ? .after(now.addingTimeInterval(6 * 3_600))
            : .atEnd
        completion(Timeline(entries: entries, policy: policy))
    }

    private func pinLimit(for family: WidgetFamily) -> Int {
        switch family {
        case .systemMedium:
            WidgetPinLayoutCapacity.medium
        case .systemLarge:
            WidgetPinLayoutCapacity.large
        default:
            WidgetPinLayoutCapacity.single
        }
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
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: KoyomiWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumContent
            case .systemLarge:
                largeContent
            case .accessoryRectangular:
                accessoryContent
            default:
                smallContent
            }
        }
        .foregroundStyle(primaryColor)
        .containerBackground(for: .widget) {
            if family == .accessoryRectangular || renderingMode != .fullColor {
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

    private var primaryColor: Color {
        renderingMode == .fullColor && family != .accessoryRectangular ? .white : .primary
    }

    private var secondaryColor: Color {
        renderingMode == .fullColor && family != .accessoryRectangular
            ? .white.opacity(0.72)
            : .secondary
    }

    @ViewBuilder
    private var smallContent: some View {
        if let pin = entry.pins.first {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(Color(koyomiHex: pin.calendarColorHex))
                        .widgetAccentable()
                    Text(pin.calendarName)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                Text(pin.titleMetadata.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 2)
                countdown(for: pin, large: true)
            }
            .widgetURL(deepLink(for: pin))
        } else {
            emptyContent
        }
    }

    @ViewBuilder
    private var mediumContent: some View {
        let usesAccessibilityLayout = dynamicTypeSize.isAccessibilitySize
        let limits = WidgetPinLayoutCapacity.mediumVisibleLimits(
            isAccessibilitySize: usesAccessibilityLayout
        )

        if usesAccessibilityLayout {
            ViewThatFits(in: .vertical) {
                pinnedListContent(limit: limits[0], rowSpacing: 5, indicatorHeight: 28)
                pinnedListContent(limit: limits[1], rowSpacing: 4, indicatorHeight: 26)
                pinnedListContent(limit: limits[2], rowSpacing: 3, indicatorHeight: 24)
            }
        } else {
            pinnedListContent(
                limit: limits[0],
                rowSpacing: 9,
                indicatorHeight: 31
            )
        }
    }

    @ViewBuilder
    private var largeContent: some View {
        let usesAccessibilityLayout = dynamicTypeSize.isAccessibilitySize
        let limits = WidgetPinLayoutCapacity.largeVisibleLimits(
            isAccessibilitySize: usesAccessibilityLayout
        )
        let titleLineLimit = WidgetPinLayoutCapacity.titleLineLimit(
            isAccessibilitySize: usesAccessibilityLayout
        )

        if usesAccessibilityLayout {
            ViewThatFits(in: .vertical) {
                pinnedListContent(limit: limits[0], rowSpacing: 6, indicatorHeight: 32, titleLineLimit: titleLineLimit)
                pinnedListContent(limit: limits[1], rowSpacing: 5, indicatorHeight: 30, titleLineLimit: titleLineLimit)
                pinnedListContent(limit: limits[2], rowSpacing: 4, indicatorHeight: 28, titleLineLimit: titleLineLimit)
                pinnedListContent(limit: limits[3], rowSpacing: 3, indicatorHeight: 26, titleLineLimit: titleLineLimit)
            }
        } else {
            ViewThatFits(in: .vertical) {
                pinnedListContent(limit: limits[0], rowSpacing: 10, indicatorHeight: 34, titleLineLimit: titleLineLimit)
                pinnedListContent(limit: limits[1], rowSpacing: 9, indicatorHeight: 33, titleLineLimit: titleLineLimit)
                pinnedListContent(limit: limits[2], rowSpacing: 8, indicatorHeight: 32, titleLineLimit: titleLineLimit)
            }
        }
    }

    @ViewBuilder
    private func pinnedListContent(
        limit: Int,
        rowSpacing: CGFloat,
        indicatorHeight: CGFloat,
        titleLineLimit: Int = 1
    ) -> some View {
        if entry.pins.isEmpty {
            emptyContent
        } else {
            let hiddenCount = WidgetPinLayoutCapacity.hiddenCount(
                totalPins: max(entry.totalActivePinCount, entry.pins.count),
                visibleLimit: limit
            )
            VStack(alignment: .leading, spacing: rowSpacing) {
                HStack(spacing: 5) {
                    Label("ピン留め", systemImage: "pin.fill")
                    Spacer(minLength: 4)
                    if hiddenCount > 0 {
                        Text("+\(hiddenCount)件")
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(secondaryColor)
                .widgetAccentable()
                ForEach(entry.pins.prefix(limit)) { pin in
                    Link(destination: deepLink(for: pin)) {
                        HStack(spacing: 10) {
                            Capsule()
                                .fill(Color(koyomiHex: pin.calendarColorHex))
                                .frame(width: 4, height: indicatorHeight)
                                .widgetAccentable()
                            Text(pin.titleMetadata.displayTitle)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(titleLineLimit)
                                .minimumScaleFactor(titleLineLimit == 1 ? 0.78 : 1)
                            Spacer(minLength: 6)
                            countdown(for: pin, large: false)
                                .frame(
                                    width: WidgetPinLayoutCapacity.countdownColumnWidth(
                                        isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
                                    ),
                                    alignment: .trailing
                                )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var accessoryContent: some View {
        if let pin = entry.pins.first {
            VStack(alignment: .leading, spacing: 2) {
                Text(pin.titleMetadata.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                countdown(for: pin, large: false)
            }
            .widgetURL(deepLink(for: pin))
        } else {
            Label("ピン留めなし", systemImage: "pin")
                .widgetAccentable()
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "pin")
                .font(.title2)
                .widgetAccentable()
            Text("予定をピン留め")
                .font(.headline)
            Text("こよみを開いて、大切な予定を選んでください。")
                .font(.caption)
                .foregroundStyle(secondaryColor)
                .lineLimit(3)
        }
    }

    private func countdown(for pin: PinnedEvent, large: Bool) -> some View {
        let presentation = CountdownCalculator.presentation(for: pin, now: entry.date)
        let isUpcoming = entry.date < pin.startDate
        let target = isUpcoming ? pin.startDate : pin.endDate
        let label = pin.isEstimatedDateWindow
            ? estimatedWidgetLabel(for: presentation.phase)
            : (isUpcoming ? "あと" : "終了まで")
        return VStack(alignment: large ? .leading : .trailing, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(secondaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if pin.isEstimatedDateWindow {
                Text(presentation.value)
                    .font(large ? .title3.bold().monospacedDigit() : .caption.bold().monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else {
                Text(target, style: .timer)
                    .font(large ? .title3.bold().monospacedDigit() : .caption.bold().monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }

    private func estimatedWidgetLabel(for phase: CountdownPhase) -> String {
        switch phase {
        case .upcoming: "見込みまで"
        case .ongoing: "期間内・遅くとも"
        case .overdue: "要確認・超過"
        case .ended: "終了"
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

@main
struct KoyomiWidgetBundle: WidgetBundle {
    var body: some Widget {
        KoyomiPinnedCountdownWidget()
    }
}
