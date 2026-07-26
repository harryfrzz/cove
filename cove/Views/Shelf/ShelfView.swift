import SwiftData
import SwiftUI

struct ShelfView: View {
    /// Capture entry point for the empty state; the shell owns the sheet.
    var onAdd: () -> Void = {}

    @Environment(\.aiServices) private var aiServices
    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]
    @State private var categorizer = ShelfCategorizer.shared
    @State private var importer = GalleryImporter.shared

    @State private var query = ""
    @State private var results: [ShelfItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @FocusState private var isFieldFocused: Bool

    /// Typing swaps the category stacks for a flat wall of matches; an empty
    /// field puts the shelf back exactly as it was.
    private var isSearchActive: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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

                        if isSearchActive {
                            searchResults
                        } else {
                            CategoryStackGrid(
                                items: items,
                                groups: categorizer.group(items)
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.immediately)
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
                    .overlay {
                        if isSearching {
                            ProgressView("Searching on device…")
                                .padding(18)
                                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: query) {
            await performSearch()
        }
        .alert("Search failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if results.isEmpty, !isSearching {
            noMatches
                .padding(.top, 60)
        } else {
            MasonryWall(items: results)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 24)
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
        VStack(spacing: 12) {
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

            searchField
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CoveTheme.ink.opacity(0.5))

            TextField("Search by meaning", text: $query)
                .font(.subheadline)
                .foregroundStyle(CoveTheme.ink)
                .focused($isFieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(CoveTheme.ink.opacity(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .glassEffect(.regular.interactive(), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { isFieldFocused = true }
    }

    private var noMatches: some View {
        VStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CoveTheme.ink)
            Text("No results for “\(query)”")
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(CoveTheme.ink)
            Text("Try a different word — search matches\nmeaning, not just exact text.")
                .font(.subheadline)
                .foregroundStyle(CoveTheme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 26)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .padding(.horizontal, 36)
    }

    // MARK: - Search

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func performSearch() async {
        guard isSearchActive else {
            results = []
            isSearching = false
            return
        }

        do {
            // Debounce: a keystroke cancels the in-flight task, so only a
            // pause in typing actually reaches the on-device index.
            try await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            isSearching = true
            results = try await aiServices.search.search(query, in: items)
            isSearching = false
        } catch is CancellationError {
            isSearching = false
        } catch {
            isSearching = false
            errorMessage = error.localizedDescription
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
