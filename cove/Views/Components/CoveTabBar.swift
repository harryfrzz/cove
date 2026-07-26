import SwiftUI

/// The three root destinations Cove switches between. Titles exist only for
/// VoiceOver — the bar itself is deliberately icon-only.
///
/// Search has no tab of its own: it lives in the shelf's own top bar, so
/// finding something happens where the things already are.
enum CoveTab: String, CaseIterable, Identifiable {
    case home
    case shelf
    case wallet
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .shelf: "Shelf"
        case .wallet: "Wallet"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .shelf: "square.stack.3d.up"
        case .wallet: "wallet.pass"
        case .profile: "person.crop.circle"
        }
    }

    /// Filled counterpart used while the tab is active.
    var selectedSystemImage: String {
        switch self {
        case .home: "house.fill"
        case .shelf: "square.stack.3d.up.fill"
        case .wallet: "wallet.pass.fill"
        case .profile: "person.crop.circle.fill"
        }
    }
}

/// Floating dock: the destinations split into two Liquid Glass pills with the
/// capture button seated dead centre between them — all inside one
/// `GlassEffectContainer` so their glass samples and blends as one surface.
struct CoveTabBar: View {
    @Binding var selection: CoveTab
    var onCamera: () -> Void = {}
    var onAdd: (AddCaptureMode) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator

    private static let iconSize: CGFloat = 54
    private static let barHeight: CGFloat = 52

    /// Split either side of the capture button. Both pills claim an equal
    /// share of the width, which is what keeps the plus optically centred.
    private static let leadingTabs: [CoveTab] = [.home, .shelf]
    private static let trailingTabs: [CoveTab] = [.wallet, .profile]

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                tabPill(Self.leadingTabs)
                addButton
                tabPill(Self.trailingTabs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func tabPill(_ tabs: [CoveTab]) -> some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
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
