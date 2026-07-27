import SwiftUI
import UIKit

/// Cove's minimal theme: warm cream and soft ink by day, the same pair
/// inverted by night. Both schemes are built from the *same* warm hue rather
/// than a neutral grey — the dark surface is a deep umber, so the glass and
/// the paper cards keep reading as the same material after dark.
///
/// Every colour is a `UIColor` with a trait-based provider rather than two
/// static values chosen at launch, so a scheme change repaints live and any
/// `.opacity()` taken off one of these stays dynamic.
enum CoveTheme {
    static let background = dynamic(
        light: UIColor(red: 0.962, green: 0.941, blue: 0.887, alpha: 1),
        dark: UIColor(red: 0.086, green: 0.078, blue: 0.070, alpha: 1)
    )

    static let ink = dynamic(
        light: UIColor(red: 0.17, green: 0.15, blue: 0.12, alpha: 1),
        dark: UIColor(red: 0.945, green: 0.933, blue: 0.902, alpha: 1)
    )

    static let inkSecondary = ink.opacity(0.55)

    /// Lifts rather than darkens after dark: a black hairline is invisible on
    /// a near-black surface.
    static let hairline = dynamic(
        light: UIColor.black.withAlphaComponent(0.08),
        dark: UIColor.white.withAlphaComponent(0.14)
    )

    /// Ink for text set over Cove's own artwork — event cards, wallet passes,
    /// album covers. Those surfaces are generated gradients that stay light in
    /// both schemes (the shader lifts every palette toward white so body text
    /// stays readable), so this one must *not* invert: in dark mode the
    /// adaptive ink above would turn near-white and disappear into them.
    static let inkOnArtwork = Color(red: 0.17, green: 0.15, blue: 0.12)

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

/// What the app does with the system's light/dark setting. Cove follows it by
/// default; the two overrides exist because a shelf full of screenshots is
/// often read in bed, and that is a choice about the app rather than about
/// the phone.
enum CoveAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "coveAppearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// `nil` hands the decision back to the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Flat background shared by every screen.
struct CoveInkBackground: View {
    var body: some View {
        CoveTheme.background
            .ignoresSafeArea()
    }
}

extension ShelfBucket {
    /// Accent used for deck icons and placeholder cards.
    var tint: Color {
        switch self {
        case .receipts: .orange
        case .events: .pink
        case .food: .yellow
        case .places: .teal
        case .documents: .indigo
        case .notes: .mint
        case .links: .blue
        case .other: .gray
        }
    }
}
