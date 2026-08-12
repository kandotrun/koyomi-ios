import SwiftUI

public struct CountdownProximityMeter: View {
    public enum Orientation: Equatable, Sendable {
        case horizontal
        case vertical
    }

    private let state: CountdownProximityState
    private let orientation: Orientation
    private let activeColor: Color
    private let trackColor: Color
    private let spacing: CGFloat

    public init(
        state: CountdownProximityState,
        orientation: Orientation = .horizontal,
        activeColor: Color? = nil,
        trackColor: Color? = nil,
        spacing: CGFloat = 3
    ) {
        self.state = state
        self.orientation = orientation
        self.activeColor = activeColor ?? state.tone.koyomiColor
        self.trackColor = trackColor ?? state.tone.koyomiColor.opacity(0.18)
        self.spacing = spacing
    }

    public var body: some View {
        Group {
            switch orientation {
            case .horizontal:
                GeometryReader { proxy in
                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(0..<state.totalSegmentCount, id: \.self) { index in
                            segment(at: index)
                                .frame(
                                    height: proxy.size.height * horizontalHeightFraction(at: index),
                                    alignment: .bottom
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            case .vertical:
                VStack(spacing: spacing) {
                    ForEach(Array((0..<state.totalSegmentCount).reversed()), id: \.self) { index in
                        segment(at: index)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func segment(at index: Int) -> some View {
        Capsule(style: .continuous)
            .fill(index == state.activeSegmentIndex ? activeColor : trackColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func horizontalHeightFraction(at index: Int) -> CGFloat {
        let step = 0.68 / CGFloat(max(state.totalSegmentCount - 1, 1))
        return 0.32 + (CGFloat(index) * step)
    }
}

public extension CountdownProximityTone {
    var koyomiColor: Color {
        switch self {
        case .calm:
            Color(red: 0.24, green: 0.72, blue: 0.78)
        case .approaching:
            Color(red: 0.31, green: 0.55, blue: 0.96)
        case .soon:
            Color(red: 0.96, green: 0.64, blue: 0.18)
        case .urgent:
            Color(red: 0.96, green: 0.34, blue: 0.25)
        case .attention:
            Color(red: 0.88, green: 0.20, blue: 0.30)
        case .inactive:
            Color.secondary
        }
    }
}
