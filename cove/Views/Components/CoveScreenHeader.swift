import SwiftUI

/// The title bar every root screen wears. Each page used to build its own, so
/// Home and Shelf both announced themselves as "Cove", Wallet fell back to a
/// system navigation bar, and Profile had no title at all — the dock is
/// icon-only, so the header is the only place that names where you are.
///
/// Layout is deliberately an overlay rather than a three-column `HStack`: the
/// title stays optically centered on the screen no matter how many controls
/// sit beside it, which is what keeps the pages feeling like one app as you
/// move between tabs with different chrome.
struct CoveScreenHeader<Leading: View, Trailing: View>: View {
    private let title: String
    private let leading: Leading
    private let trailing: Trailing

    init(
        _ title: String,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            leading
            Spacer(minLength: 0)
            trailing
        }
        // Matches the glass circles the controls sit in, so a header with no
        // controls is exactly as tall as one that has them.
        .frame(minHeight: 36)
        .overlay {
            Text(title)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(CoveTheme.ink)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

extension CoveScreenHeader where Leading == EmptyView {
    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.init(title, leading: { EmptyView() }, trailing: trailing)
    }
}

extension CoveScreenHeader where Leading == EmptyView, Trailing == EmptyView {
    init(_ title: String) {
        self.init(title, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

/// Round glass control sized to sit in a header slot. Shared so the stethoscope,
/// gear, and item count are all the same object at the same size.
struct CoveHeaderIcon: View {
    let systemImage: String
    var isInteractive = true

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(CoveTheme.ink.opacity(0.8))
            .frame(width: 36, height: 36)
            .glassEffect(isInteractive ? .regular.interactive() : .regular, in: Circle())
    }
}

#Preview("Header") {
    ZStack(alignment: .top) {
        CoveInkBackground()
        VStack(spacing: 18) {
            CoveScreenHeader("Home") {
                Text("20")
                    .font(.system(.subheadline, design: .serif, weight: .bold))
                    .foregroundStyle(.orange)
                    .frame(minWidth: 36, minHeight: 36)
                    .glassEffect(.regular, in: Circle())
            }
            CoveScreenHeader(
                "Profile",
                leading: { CoveHeaderIcon(systemImage: "stethoscope") },
                trailing: { CoveHeaderIcon(systemImage: "gearshape") }
            )
            CoveScreenHeader("Chat")
        }
        .padding(20)
    }
}
