import ActivityKit
import SwiftUI
import WidgetKit

struct KoyomiPinnedEventLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PinnedEventActivityAttributes.self) { context in
            lockScreenView(context: context)
                .widgetURL(deepLink(for: context.attributes.eventID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "pin.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .privacySensitive()
                        Text(context.state.calendarName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .privacySensitive()
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdownText(
                        startDate: context.state.startDate,
                        font: .caption.monospacedDigit().bold()
                    )
                    .foregroundStyle(.white)
                    .privacySensitive()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(
                        timerInterval: countdownWindow(endingAt: context.state.startDate),
                        countsDown: false
                    )
                    .tint(.white.opacity(0.72))
                    .privacySensitive()
                    .accessibilityHidden(true)
                }
            } compactLeading: {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
            } compactTrailing: {
                countdownText(
                    startDate: context.state.startDate,
                    font: .caption2.monospacedDigit().bold()
                )
                .foregroundStyle(.primary)
                .frame(maxWidth: 64)
                .minimumScaleFactor(0.65)
                .privacySensitive()
            } minimal: {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.primary)
                    .accessibilityLabel("ピン留め予定")
            }
            .widgetURL(deepLink(for: context.attributes.eventID))
            .keylineTint(accentColor(for: context.state))
        }
    }

    private func lockScreenView(
        context: ActivityViewContext<PinnedEventActivityAttributes>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "pin.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(accentColor(for: context.state).opacity(0.35), in: .circle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(2)
                        .privacySensitive()
                    Text(context.state.calendarName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .privacySensitive()
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(countdownLabel(for: context.state))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.72))
                    countdownText(
                        startDate: context.state.startDate,
                        font: .title3.monospacedDigit().bold()
                    )
                    .foregroundStyle(.white)
                    .privacySensitive()
                    .minimumScaleFactor(0.72)
                }
            }

            ProgressView(
                timerInterval: countdownWindow(endingAt: context.state.startDate),
                countsDown: false
            )
            .tint(.white.opacity(0.72))
            .privacySensitive()
            .accessibilityHidden(true)

            Text(context.state.startDate, format: startDateFormat(for: context.state))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .privacySensitive()
        }
        .foregroundStyle(.white)
        .padding(16)
        .activityBackgroundTint(Color(koyomiHex: "10213D").opacity(0.96))
        .activitySystemActionForegroundColor(.white)
        .accessibilityElement(children: .combine)
    }

    private func countdownText(startDate: Date, font: Font) -> some View {
        Text(
            timerInterval: countdownWindow(endingAt: startDate),
            pauseTime: startDate,
            countsDown: true,
            showsHours: true
        )
        .font(font)
        .lineLimit(1)
    }

    private func countdownWindow(endingAt startDate: Date) -> ClosedRange<Date> {
        startDate.addingTimeInterval(-PinnedLiveActivityPolicy.countdownWindow)...startDate
    }

    private func countdownLabel(
        for state: PinnedEventActivityAttributes.ContentState
    ) -> String {
        state.isEstimatedDateWindow ? "見込み期間まで" : "開始まで"
    }

    private func startDateFormat(
        for state: PinnedEventActivityAttributes.ContentState
    ) -> Date.FormatStyle {
        var format = Date.FormatStyle.dateTime
            .month()
            .day()
            .weekday()
            .locale(Locale(identifier: "ja_JP"))
        if !state.isAllDay {
            format = format.hour().minute()
        }
        return format
    }

    private func accentColor(
        for state: PinnedEventActivityAttributes.ContentState
    ) -> Color {
        Color(koyomiHex: state.calendarColorHex)
    }

    private func deepLink(for eventID: String) -> URL? {
        let encoded = eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventID
        return URL(string: "koyomi://event/\(encoded)")
    }
}
