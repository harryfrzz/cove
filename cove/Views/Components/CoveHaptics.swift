import UIKit

/// Small, consistent tactile cues for Cove's custom controls. Keeping these
/// calls in one place avoids accidentally layering SwiftUI sensory feedback
/// and UIKit generators for the same interaction.
@MainActor
enum CoveHaptics {
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .soft) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}
