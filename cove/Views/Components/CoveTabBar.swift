import SwiftUI

/// The three root destinations Cove switches between. Titles exist only for
/// VoiceOver — the bar itself is deliberately icon-only.
enum CoveTab: String, CaseIterable, Identifiable {
    case shelf
    case search
    case wallet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shelf: "Shelf"
        case .search: "Search"
        case .wallet: "Wallet"
        }
    }

    var systemImage: String {
        switch self {
        case .shelf: "square.stack.3d.up"
        case .search: "magnifyingglass"
        case .wallet: "wallet.pass"
        }
    }

    /// Filled counterpart used while the tab is active. Magnifying glass has
    /// no filled variant, so it stays put and reads as selected by tint alone.
    var selectedSystemImage: String {
        switch self {
        case .shelf: "square.stack.3d.up.fill"
        case .search: "magnifyingglass"
        case .wallet: "wallet.pass.fill"
        }
    }
}

/// Floating dock: a Liquid Glass pill of icon-only destinations, a standalone
/// search button, and the capture button — all inside one
/// `GlassEffectContainer` so their glass samples and blends as one surface.
struct CoveTabBar: View {
    @Binding var selection: CoveTab
    var onCamera: () -> Void = {}
    var onAdd: (AddCaptureMode) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator

    private static let iconSize: CGFloat = 54
    private static let barHeight: CGFloat = 52

    /// Search sits on its own — it reads as an action, not a shelf you browse.
    private static let pillTabs: [CoveTab] = [.shelf, .wallet]

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                tabPill
                searchButton
                addButton
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var tabPill: some View {
        HStack(spacing: 2) {
            ForEach(Self.pillTabs) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 5)
        .frame(height: Self.barHeight)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private var searchButton: some View {
        let isSelected = selection == .search

        return Button {
            select(.search)
        } label: {
            Image(systemName: CoveTab.search.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : CoveTheme.ink.opacity(0.75))
                .frame(width: Self.barHeight, height: Self.barHeight)
                .background {
                    if isSelected {
                        Circle().fill(CoveTheme.ink)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(CoveTab.search.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
                .frame(width: Self.iconSize, height: Self.barHeight - 8)
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
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.glassProminent)
        .tint(CoveTheme.ink)
        .controlSize(.large)
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
