import SwiftUI

/// Cove's minimal light theme: warm cream surface, soft ink text.
enum CoveTheme {
    static let background = Color(red: 0.962, green: 0.941, blue: 0.887)
    static let ink = Color(red: 0.17, green: 0.15, blue: 0.12)
    static let inkSecondary = Color(red: 0.17, green: 0.15, blue: 0.12).opacity(0.55)
    static let hairline = Color.black.opacity(0.08)
}

/// Flat cream background shared by every screen.
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
