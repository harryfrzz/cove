import SwiftData
import SwiftUI

struct ShelfView: View {
    /// Capture entry point for the empty state; the shell owns the sheet.
    var onAdd: () -> Void = {}

    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]
    @State private var categorizer = ShelfCategorizer.shared
    @State private var importer = GalleryImporter.shared

    var body: some View {
        NavigationStack {
            ZStack {
                CoveInkBackground()

                if items.isEmpty, !importer.isImporting {
                    emptyState
                } else {
                    ScrollView {
                        if importer.isImporting {
                            importProgressChip
                                .padding(.top, 4)
                                .padding(.bottom, 8)
                        }

                        CategoryStackGrid(
                            items: items,
                            groups: categorizer.group(items)
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    // Bar (not a plain inset) so cards scrolling underneath get
                    // the system's own progressive blur, like a native nav bar.
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
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var importProgressChip: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Indexing your library · \(importer.importedCount)/\(importer.totalCount)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(CoveTheme.inkSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
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

            Text("\(items.count)")
                .font(.system(.subheadline, design: .serif, weight: .bold))
                .foregroundStyle(.orange)
                .frame(minWidth: 36, minHeight: 36)
                .glassEffect(.regular, in: Circle())
                .accessibilityLabel("\(items.count) items")
        }
        // Overlaid so the wordmark stays optically centered whatever sits
        // in the leading slot.
        .overlay {
            Text("Cove")
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(CoveTheme.ink)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CoveTheme.ink)

            VStack(spacing: 8) {
                Text("Your shelf is clear")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(CoveTheme.ink)
                Text("Drop in a screenshot, link, or thought.\nCove keeps it local and easy to find.")
                    .font(.subheadline)
                    .foregroundStyle(CoveTheme.inkSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                onAdd()
            } label: {
                Label("Add your first item", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(CoveTheme.ink)
            .padding(.top, 6)
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 30)
        .glassEffect(.regular, in: .rect(cornerRadius: 34))
        .padding(36)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Empty shelf") {
    ShelfView()
        .modelContainer(for: ShelfItem.self, inMemory: true)
        .environment(\.aiServices, .mock)
}
