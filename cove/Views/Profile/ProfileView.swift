import SwiftData
import SwiftUI

/// Profile tab. Cove has no account system — the name is stored locally and
/// exists so the shelf feels like *yours*, not so anything can be signed into.
///
/// The page is one indexed-files headline over the switches that belong to the
/// app rather than to the shelf. It all sits on Cove's flat canvas, where glass
/// reads quietly: with nothing behind it to refract, the material falls back to
/// a soft tint and its edge highlight.
struct ProfileView: View {
    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]
    /// Only read by "Delete everything" — conversations have no other presence
    /// on this page.
    @Query private var threads: [ChatThread]
    @Environment(\.modelContext) private var modelContext
    @State private var isConfirmingEraseAll = false
    @State private var importer = GalleryImporter.shared

    /// Stamped the first time this screen is opened. Deliberately *not* derived
    /// from the oldest item: imported screenshots carry the photo's own date, so
    /// that would claim you'd been using Cove since whenever you took them.
    @AppStorage("profileStartedAt") private var startedAt: Double = 0

    /// Read by the shell, set here — the one place in Cove that is a setting
    /// rather than a piece of the shelf.
    @AppStorage(CoveAppearance.storageKey) private var appearance = CoveAppearance.system

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                CoveInkBackground()

                ScrollView {
                    VStack(spacing: 26) {
                        hero
                        footer
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 36)
                }
                .scrollIndicators(.hidden)
                .safeAreaBar(edge: .top) {
                    topBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 6)
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

    // MARK: - Derived

    private var unfinishedCount: Int {
        items.filter { $0.processingState != .ready }.count
    }

    private func count(of state: ShelfProcessingState) -> Int {
        items.filter { $0.processingState == state }.count
    }

    /// Pictures Cove has finished putting through the pipeline — the headline
    /// number. Notes and links are excluded: they never needed indexing in the
    /// first place, so counting them would flatter the figure.
    private var indexedImageCount: Int {
        items.filter {
            ($0.kind == .image || $0.kind == .screenshot) && $0.processingState == .ready
        }
        .count
    }

    private var totalImageCount: Int {
        items.filter { $0.kind == .image || $0.kind == .screenshot }.count
    }

    /// How full the liquid sits: the share of pictures that are done. An empty
    /// library reads as full rather than empty — there is nothing left to do.
    private var indexedFraction: Double {
        guard totalImageCount > 0 else { return 1 }
        return Double(indexedImageCount) / Double(totalImageCount)
    }

    private var memberSince: String? {
        guard startedAt > 0 else { return nil }
        return Date(timeIntervalSince1970: startedAt)
            .formatted(.dateTime.month(.abbreviated).year())
    }

    // MARK: - Chrome

    private var topBar: some View {
        CoveScreenHeader("Profile") {
#if DEBUG
            NavigationLink {
                AIDiagnosticsView()
            } label: {
                CoveHeaderIcon(systemImage: "stethoscope")
            }
            .accessibilityLabel("AI diagnostics")
#endif
        } trailing: {
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                CoveHeaderIcon(systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("System settings")
        }
    }

    // MARK: - Hero

    /// Avatar and name, with the item count set as a lens directly over the
    /// gradient rather than boxed in a card.
    private var hero: some View {
        VStack(spacing: 0) {
            LiquidNumber(
                text: indexedImageCount.formatted(
                    .number.notation(.compactName).precision(.fractionLength(0...1))
                ),
                level: indexedFraction,
                accessibilityLabel: "\(indexedImageCount) pictures indexed"
            )
            .padding(.top, 18)

            Text("Files indexed")
                .font(.system(size: 13, weight: .semibold))
                .tracking(2.2)
                .textCase(.uppercase)
                .foregroundStyle(CoveTheme.ink.opacity(0.5))
                .padding(.top, 6)

            Text(subtitleLine)
                .font(.footnote)
                .foregroundStyle(CoveTheme.ink.opacity(0.42))
                .padding(.top, 6)
        }
    }

    private var subtitleLine: String {
        var parts = ["\(items.count) saved"]
        if let memberSince { parts.append("since \(memberSince)") }
        if unfinishedCount > 0 { parts.append("\(unfinishedCount) working") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Footer

    /// The two things worth doing from here, plus the promise the app is built
    /// on. Unioned so the row reads as one piece of glass with a seam, not as
    /// separate buttons.
    private var footer: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.subheadline)
                        .foregroundStyle(CoveTheme.ink.opacity(0.7))

                    Text("Extraction, categorising, and search all run here. Nothing you save is uploaded.")
                        .font(.footnote)
                        .foregroundStyle(CoveTheme.ink.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))

                appearanceControl
                modelsControl
                libraryControl

                if !items.isEmpty {
                    eraseAllControl
                }
            }
        }
    }

    /// The one row on this page that leads somewhere rather than doing
    /// something. Status is summarised from the language model alone: the
    /// encoders ship in the binary and are never the thing that needs setting
    /// up, so a row that said "needs setup" for them would be pointing at a
    /// problem the user cannot act on.
    private var modelsControl: some View {
        NavigationLink {
            ModelSetupView()
        } label: {
            footerRow(
                "On-device models",
                detail: FoundationModelsService.availabilityError() == nil
                    ? "Ready"
                    : "Needs setup",
                systemImage: "cpu"
            )
        }
        .buttonStyle(.plain)
    }

    /// Light, dark, or whatever the phone is doing. Sits with the other two
    /// footer rows because it is the same kind of thing: a switch for the app,
    /// not a view of the shelf.
    private var appearanceControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: appearance.systemImage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CoveTheme.ink.opacity(0.75))
                    .frame(width: 22)
                    .contentTransition(.symbolEffect(.replace))

                Text("Appearance")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CoveTheme.ink)

                Spacer(minLength: 0)
            }

            Picker("Appearance", selection: $appearance) {
                ForEach(CoveAppearance.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    /// The one place to get everything back off the device. Kept at the very
    /// bottom of Profile, behind a confirmation that names the count — an
    /// unqualified "Delete all" is too easy to tap by accident.
    private var eraseAllControl: some View {
        Button(role: .destructive) {
            isConfirmingEraseAll = true
        } label: {
            footerRow(
                "Delete everything",
                detail: "\(items.count) items",
                systemImage: "trash"
            )
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "Delete all \(items.count) items?",
            isPresented: $isConfirmingEraseAll,
            titleVisibility: .visible
        ) {
            Button("Delete everything", role: .destructive) {
                modelContext.deleteShelfItems(items)
                modelContext.deleteChatThreads(threads)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every screenshot, note, pass and conversation Cove has saved is removed from this device. Your photo library itself is untouched. This can't be undone.")
        }
    }

    @ViewBuilder
    private var libraryControl: some View {
        if importer.isDenied {
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                footerRow("Photo access is off", detail: "Turn it on", systemImage: "exclamationmark.triangle")
            }
            .buttonStyle(.plain)
        } else if importer.isImporting {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Indexing · \(importer.importedCount)/\(importer.totalCount)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CoveTheme.ink)
                Spacer(minLength: 0)
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            Button {
                Task { await importer.importLibrary() }
            } label: {
                footerRow(
                    "Re-scan library",
                    detail: versionLabel,
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func footerRow(_ title: String, detail: String?, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CoveTheme.ink.opacity(0.75))
                .frame(width: 22)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CoveTheme.ink)

            Spacer(minLength: 0)

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(CoveTheme.ink.opacity(0.45))
            }
        }
        .padding(16)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
    }

    private var versionLabel: String? {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return "Cove \(version)"
    }
}


#Preview("Profile") {
    ProfileView()
        .modelContainer(for: [ShelfItem.self, ChatThread.self], inMemory: true)
        .environment(\.aiServices, .mock)
}
