import SwiftData
import SwiftUI

/// Profile tab: who this shelf belongs to, what's in it, and the few controls
/// worth surfacing. Cove has no account system — the name is stored locally and
/// exists so the shelf feels like *yours*, not so anything can be signed into.
struct ProfileView: View {
    var onOpenShelf: () -> Void = {}
    var onOpenWallet: () -> Void = {}

    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]
    @State private var categorizer = ShelfCategorizer.shared
    @State private var importer = GalleryImporter.shared

    @AppStorage("profileDisplayName") private var displayName = ""
    /// Stamped the first time this screen is opened. Deliberately *not* derived
    /// from the oldest item: imported screenshots carry the photo's own date, so
    /// that would claim you'd been using Cove since whenever you took them.
    @AppStorage("profileStartedAt") private var startedAt: Double = 0
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                CoveInkBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        identityCard
                        statGrid
                        librarySection
                        if unfinishedCount > 0 { processingSection }
                        aboutSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.immediately)
                .safeAreaBar(edge: .top) {
                    topBar
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                // The floating dock is its own glass; no wash under it.
                .scrollEdgeEffectHidden(true, for: .bottom)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            if startedAt == 0 { startedAt = Date.now.timeIntervalSince1970 }
        }
    }

    // MARK: - Derived counts

    private var walletCount: Int {
        items.filter(\.isInWallet).count
    }

    private var categoryCount: Int {
        categorizer.group(items).count
    }

    private var unfinishedCount: Int {
        items.filter { $0.processingState != .ready }.count
    }

    private func count(of state: ShelfProcessingState) -> Int {
        items.filter { $0.processingState == state }.count
    }

    /// First letters of the typed name, falling back to the app's own mark so
    /// the avatar never renders empty.
    private var initials: String {
        let parts = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        return parts.isEmpty ? "C" : String(parts).uppercased()
    }

    private var memberSince: String? {
        guard startedAt > 0 else { return nil }
        return Date(timeIntervalSince1970: startedAt)
            .formatted(.dateTime.month(.wide).year())
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 8) {
#if DEBUG
            NavigationLink {
                AIDiagnosticsView()
            } label: {
                Image(systemName: "stethoscope")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CoveTheme.ink.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular, in: Circle())
            }
            .accessibilityLabel("AI diagnostics")
#endif

            Spacer(minLength: 0)
        }
        .overlay {
            Text("Profile")
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(CoveTheme.ink)
        }
    }

    // MARK: - Identity

    private var identityCard: some View {
        VStack(spacing: 14) {
            Text(initials)
                .font(.system(size: 30, design: .serif).weight(.semibold))
                .foregroundStyle(CoveTheme.ink)
                .frame(width: 84, height: 84)
                .background {
                    Circle()
                        .fill(.white.opacity(0.7))
                        .overlay {
                            Circle().strokeBorder(CoveTheme.hairline, lineWidth: 1)
                        }
                }
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                TextField("Add your name", text: $displayName)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(CoveTheme.ink)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .onSubmit { isNameFocused = false }

                if let memberSince {
                    Text("Collecting since \(memberSince)")
                        .font(.footnote)
                        .foregroundStyle(CoveTheme.inkSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 20)
        .paperCard(cornerRadius: 24)
    }

    // MARK: - Stats

    private var statGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
            spacing: 12
        ) {
            ProfileStat(
                value: items.count,
                label: "Items saved",
                systemImage: "square.stack.3d.up",
                tint: CoveTheme.ink,
                action: onOpenShelf
            )
            ProfileStat(
                value: walletCount,
                label: "Wallet passes",
                systemImage: "wallet.pass",
                tint: .orange,
                action: onOpenWallet
            )
            ProfileStat(
                value: categoryCount,
                label: "Categories",
                systemImage: "square.grid.2x2",
                tint: CoveTheme.ink,
                action: onOpenShelf
            )
            ProfileStat(
                value: count(of: .ready),
                label: "Fully indexed",
                systemImage: "checkmark.seal",
                tint: .green,
                action: onOpenShelf
            )
        }
    }

    // MARK: - Library

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Photo library")

            VStack(alignment: .leading, spacing: 10) {
                if importer.isDenied {
                    Label(
                        "Photo access is off. Turn it on in Settings to index your library.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(CoveTheme.inkSecondary)

                    Button("Open Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.glass)
                } else if importer.isImporting {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Indexing · \(importer.importedCount)/\(importer.totalCount)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(CoveTheme.inkSecondary)
                    }
                } else {
                    Text("Cove indexes new screenshots automatically. Re-scan if something looks missing.")
                        .font(.footnote)
                        .foregroundStyle(CoveTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await importer.importLibrary() }
                    } label: {
                        Label("Re-scan library", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .tint(CoveTheme.ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .paperCard()
        }
    }

    // MARK: - Processing

    private var processingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Still working")

            VStack(spacing: 0) {
                statusRow("Queued", count: count(of: .queued), systemImage: "clock")
                divider
                statusRow("Processing", count: count(of: .processing), systemImage: "wand.and.sparkles")
                divider
                statusRow("Failed", count: count(of: .failed), systemImage: "exclamationmark.triangle", tint: .red)
            }
            .padding(.vertical, 4)
            .paperCard()
        }
    }

    private func statusRow(
        _ title: String,
        count: Int,
        systemImage: String,
        tint: Color = CoveTheme.ink
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(count > 0 ? tint : CoveTheme.inkSecondary)
                .frame(width: 22)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(CoveTheme.ink)

            Spacer(minLength: 0)

            Text("\(count)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(count > 0 ? tint : CoveTheme.inkSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("About")

            VStack(alignment: .leading, spacing: 10) {
                Label("Everything stays on this device", systemImage: "lock.shield")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CoveTheme.ink)

                Text("Text extraction, categorising, and search all run on-device. Nothing you save is uploaded.")
                    .font(.footnote)
                    .foregroundStyle(CoveTheme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                    Text("Cove \(version)")
                        .font(.caption)
                        .foregroundStyle(CoveTheme.inkSecondary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .paperCard()
        }
    }

    // MARK: - Pieces

    private var divider: some View {
        Rectangle()
            .fill(CoveTheme.hairline)
            .frame(height: 1)
            .padding(.leading, 50)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.headline, design: .serif, weight: .semibold))
            .foregroundStyle(CoveTheme.ink)
    }
}

// MARK: - Stat tile

private struct ProfileStat: View {
    let value: Int
    let label: String
    let systemImage: String
    var tint: Color = CoveTheme.ink
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12), in: .rect(cornerRadius: 10))

                Text("\(value)")
                    .font(.system(.title, design: .serif, weight: .semibold).monospacedDigit())
                    .foregroundStyle(CoveTheme.ink)
                    .contentTransition(.numericText())

                Text(label)
                    .font(.footnote)
                    .foregroundStyle(CoveTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .paperCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

// MARK: - Paper card

/// Matches the home dashboard's card treatment so the two tabs read as one app.
private struct ProfilePaperCard: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(.white.opacity(0.65))
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(CoveTheme.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
    }
}

private extension View {
    func paperCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(ProfilePaperCard(cornerRadius: cornerRadius))
    }
}

#Preview("Profile") {
    ProfileView()
        .modelContainer(for: ShelfItem.self, inMemory: true)
        .environment(\.aiServices, .mock)
}
