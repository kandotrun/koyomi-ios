import UIKit

@MainActor
enum KoyomiHaptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let impactGenerator = UIImpactFeedbackGenerator(style: .medium)

    static func perform(_ interaction: KoyomiInteraction) {
        switch KoyomiHapticPolicy.feedback(for: interaction) {
        case .selection:
            selectionGenerator.prepare()
            selectionGenerator.selectionChanged()
        case .impact:
            impactGenerator.prepare()
            impactGenerator.impactOccurred(intensity: 0.82)
        }
    }
}
