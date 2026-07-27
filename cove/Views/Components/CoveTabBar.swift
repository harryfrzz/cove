import SwiftUI

/// The three root destinations Cove switches between. Titles exist only for
/// VoiceOver — the bar itself is deliberately icon-only.
///
/// Search has no tab of its own: it lives in the shelf's own top bar, so
/// finding something happens where the things already are.
enum CoveTab: String, CaseIterable, Identifiable {
    case home
    case shelf
    case chat
    case wallet
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .shelf: "Shelf"
        case .chat: "Chat"
        case .wallet: "Wallet"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .shelf: "square.stack.3d.up"
        case .chat: "bubble.left.and.bubble.right"
        case .wallet: "wallet.pass"
        case .profile: "person.crop.circle"
        }
    }

    /// Filled counterpart used while the tab is active.
    var selectedSystemImage: String {
        switch self {
        case .home: "house.fill"
        case .shelf: "square.stack.3d.up.fill"
        case .chat: "bubble.left.and.bubble.right.fill"
        case .wallet: "wallet.pass.fill"
        case .profile: "person.crop.circle.fill"
        }
    }
}

/// Floating dock: one Liquid Glass pill holding every destination, with the
/// capture button standing free at the trailing end. Keeping the plus off the
/// pill is deliberate — navigation and the one action are different kinds of
/// control, and a separate button can never be mistaken for a fifth tab. Both
/// live in one `GlassEffectContainer` so their glass samples as one surface.
struct CoveTabBar: View {
    @Binding var selection: CoveTab
    var onCamera: () -> Void = {}
    var onAdd: (AddCaptureMode) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator

    // Five destinations share the pill with the free-standing plus, so the
    // per-icon minimum has to leave the row room on a narrow phone; the
    // `maxWidth: .infinity` below spreads them out again wherever there is
    // space.
    private static let iconSize: CGFloat = 44
    private static let barHeight: CGFloat = 52

    /// Total height the dock occupies, its own vertical padding included.
    /// The shell hangs the dock off the root as a bottom safe-area inset, but
    /// that inset does not reach screens nested in their own navigation stack
    /// — so a page with bottom-anchored chrome of its own (Chat's composer)
    /// clears the dock by insetting this much itself.
    static let occupiedHeight: CGFloat = barHeight + 12

    var body: some View {
        // No `GlassEffectContainer` around these two on purpose. The container
        // blends its children into one glass surface, which dragged the solid
        // ink circle into the pill's shape and left it with a smeared edge.
        // The plus is not glass, so it has no business being blended.
        HStack(spacing: 10) {
            tabPill
            addButton
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var tabPill: some View {
        HStack(spacing: 2) {
            ForEach(CoveTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity)
        .frame(height: Self.barHeight)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private func select(_ tab: CoveTab) {
        guard selection != tab else { return }
        if reduceMotion {
            selection = tab
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                selection = tab
            }
        }
    }

    private func tabButton(for tab: CoveTab) -> some View {
        let isSelected = selection == tab

        return Button {
            select(tab)
        } label: {
            Image(systemName: isSelected ? tab.selectedSystemImage : tab.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(isSelected ? CoveTheme.ink : CoveTheme.ink.opacity(0.42))
                .frame(minWidth: Self.iconSize, maxWidth: .infinity)
                .frame(height: Self.barHeight - 8)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(CoveTheme.ink.opacity(0.10))
                            .matchedGeometryEffect(id: "coveTabIndicator", in: indicator)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var addButton: some View {
        Menu {
            if CameraCaptureView.isAvailable {
                Button {
                    onCamera()
                } label: {
                    Label("Camera", systemImage: "camera")
                }
            }
            ForEach(AddCaptureMode.allCases) { mode in
                Button {
                    onAdd(mode)
                } label: {
                    Label(mode.rawValue, systemImage: mode.systemImage)
                }
            }
        } label: {
            // Solid ink, matched to the pill's height so the two read as one
            // dock: the filled circle is what separates the action from the
            // destinations beside it.
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(CoveTheme.background)
                .frame(width: Self.barHeight, height: Self.barHeight)
                .background(CoveTheme.ink, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add")
        .accessibilityHint("Add a screenshot, link, or note")
    }
}

#Preview("Tab bar") {
    @Previewable @State var selection: CoveTab = .shelf

    ZStack {
        CoveInkBackground()
        VStack {
            Spacer()
            CoveTabBar(selection: $selection)
        }
    }
}
