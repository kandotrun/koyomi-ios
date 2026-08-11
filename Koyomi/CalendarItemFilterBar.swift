import SwiftUI

struct CalendarItemFilterBar: View {
    @ObservedObject var model: CalendarViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ForEach(CalendarItemFilter.allCases) { filter in
                        filterButton(filter)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .contentMargins(.horizontal, 20, for: .scrollContent)
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar-item-filter")
    }

    @ViewBuilder
    private func filterButton(_ filter: CalendarItemFilter) -> some View {
        let button = Button {
            KoyomiHaptics.perform(.switchAgenda)
            if EventTagAnimationPolicy.shouldAnimate(reduceMotionEnabled: reduceMotion) {
                withAnimation(.snappy) { model.selectItemFilter(filter) }
            } else {
                model.selectItemFilter(filter)
            }
        } label: {
            Text(filter.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 2)
        }
        .accessibilityValue(model.itemFilter == filter ? "選択中" : "")
        .accessibilityIdentifier("item-filter-\(filter.rawValue)")

        if model.itemFilter == filter {
            button
                .buttonStyle(.glassProminent)
                .tint(filter.tint)
        } else {
            button
                .buttonStyle(.glass)
                .tint(filter.tint)
        }
    }
}

private extension CalendarItemFilter {
    var title: String {
        switch self {
        case .all: "すべて"
        case .events: "予定"
        case .estimatedWindows: "見込み"
        case .openTasks: "未完了"
        case .completedTasks: "完了済み"
        }
    }

    var tint: Color {
        switch self {
        case .all: .accentColor
        case .events: Color(koyomiHex: "5B8DEF")
        case .estimatedWindows: .purple
        case .openTasks: .orange
        case .completedTasks: .green
        }
    }
}
