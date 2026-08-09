import SwiftUI

struct KoyomiBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(koyomiHex: "081426"), Color(koyomiHex: "101C35"), Color(koyomiHex: "19152D")]
                    : [Color(koyomiHex: "EAF5FF"), Color(koyomiHex: "F8F5FF"), Color(koyomiHex: "FFF7EF")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(colorScheme == .dark ? 0.8 : 0.9)

            Circle()
                .fill(Color(koyomiHex: "50B8FF").opacity(colorScheme == .dark ? 0.18 : 0.22))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: 150, y: -290)

            Circle()
                .fill(Color(koyomiHex: "9A78F0").opacity(colorScheme == .dark ? 0.12 : 0.14))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: -170, y: 310)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private struct KoyomiGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let tint: Color
    let cornerRadius: CGFloat
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background(colorScheme == .dark ? Color(koyomiHex: "202737") : .white, in: shape)
                .overlay(shape.strokeBorder(tint.opacity(0.28), lineWidth: 1))
        } else if interactive {
            content.glassEffect(
                .regular.tint(tint.opacity(0.18)).interactive(),
                in: shape
            )
        } else {
            content.glassEffect(
                .regular.tint(tint.opacity(0.16)),
                in: shape
            )
        }
    }
}

extension View {
    func koyomiGlass(
        tint: Color = Color(koyomiHex: "5B8DEF"),
        cornerRadius: CGFloat = 26,
        interactive: Bool = false
    ) -> some View {
        modifier(
            KoyomiGlassModifier(
                tint: tint,
                cornerRadius: cornerRadius,
                interactive: interactive
            )
        )
    }
}
