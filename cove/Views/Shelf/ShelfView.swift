import SwiftData
import SwiftUI

struct ShelfView: View {
    /// Capture entry point for the empty state; the shell owns the sheet.
    var onAdd: () -> Void = {}

    @Environment(\.aiServices) private var aiServices
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]
    @State private var categorizer = ShelfCategorizer.shared
    @State private var importer = GalleryImporter.shared

    @State private var query = ""
    @State private var results: [ShelfItem] = []
    @State private var isSearching = false
    /// `nil` until a long press starts a selection on the results wall.
    @State private var selection: Set<UUID>?
    @State private var errorMessage: String?
    @State private var pullDistance: CGFloat = 0
    @State private var isRefreshingShelf = false
    @State private var isPullGestureActive = false
    @State private var isSearchPresented = false
    @State private var isChatPresented = false
    @FocusState private var isFieldFocused: Bool

    private static let morph = Animation.spring(response: 0.42, dampingFraction: 0.82)

    /// Typing swaps the category stacks for a flat wall of matches; an empty
    /// field puts the shelf back exactly as it was.
    private var isSearchActive: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CoveInkBackground()

                ScrollView {
                    if items.isEmpty, !importer.isImporting {
                        emptyState
                            .padding(.top, 32)
                    } else {
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
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.immediately)
                .onScrollPhaseChange { _, phase in
                    switch phase {
                    case .tracking, .interacting:
                        isPullGestureActive = true
                    default:
                        isPullGestureActive = false
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(
                        0,
                        -(geometry.contentOffset.y + geometry.contentInsets.top)
                    )
                } action: { _, distance in
                    pullDistance = min(distance, 140)
                    if isPullGestureActive, distance >= 86, !isRefreshingShelf {
                        Task {
                            await refreshShelf()
                        }
                    }
                }
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
            .toolbar(.hidden, for: .navigationBar)
            // Sits above the floating dock rather than replacing it — the dock
            // is an inset on the shell, so this stacks on top of it.
            .safeAreaInset(edge: .bottom) {
                if selection != nil {
                    SelectionActionBar(selection: $selection, items: results)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.28), value: selection == nil)
        }
        .task(id: query) {
            await performSearch()
        }
        .task {
#if DEBUG
            // Lets a screenshot run catch the open state; the field is
            // otherwise only reachable by tapping.
            if ProcessInfo.processInfo.arguments.contains("--open-search") {
                isSearchPresented = true
            }
#endif
        }
        // Presented rather than pushed: chat is not a place inside the shelf,
        // and a sheet keeps the dock and this page underneath it.
        .sheet(isPresented: $isChatPresented) {
            ChatView(bottomInset: 0)
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
            MasonryWall(items: results, selection: $selection)
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

    /// One row in both states. Search used to open on a second line, which made
    /// the header taller mid-gesture and shoved the whole wall down; now the
    /// field takes the row the controls were already sitting in.
    /// A plain `HStack`, deliberately. Wrapping this row in a
    /// `GlassEffectContainer` — as the dock does — stopped the magnifier from
    /// registering taps at all, and merging two 36pt circles buys nothing here.
    private var topBar: some View {
        HStack(spacing: 10) {
            if isSearchPresented {
                // Grows from the trailing edge, which is where the magnifier it
                // was tapped on sits. A matched-geometry pair was tried first
                // and is the wrong tool: the field would be the non-source, so
                // its frame came from a capsule that only exists while search
                // is *closed*.
                searchField
                    .transition(
                        .scale(scale: 0.04, anchor: .trailing)
                            .combined(with: .opacity)
                    )
            } else {
                chatHistoryButton
                    .transition(.scale(scale: 0.6).combined(with: .opacity))

                Spacer(minLength: 0)
            }

            Button(action: toggleSearch) {
                CoveHeaderIcon(
                    systemImage: isSearchPresented ? "xmark" : "magnifyingglass",
                    isInteractive: false
                )
                .contentTransition(.symbolEffect(.replace))
                // Explicit, so the tap area is the whole circle rather than
                // whatever the glyph happens to cover.
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSearchPresented ? "Close search" : "Search")
        }
        .frame(minHeight: 36)
        .overlay {
            CoveRefreshingTitle(
                pullDistance: pullDistance,
                isRefreshing: isRefreshingShelf
            )
            // The title would otherwise sit on top of the open field.
            .opacity(isSearchPresented ? 0 : 1)
            .allowsHitTesting(false)
        }
    }

    /// Home's leading control. It replaced the item count: chat is the one
    /// thing on this page you cannot get to any other way, and Profile still
    /// reports how much is saved.
    private var chatHistoryButton: some View {
        Button {
            CoveHaptics.selection()
            isChatPresented = true
        } label: {
            CoveHeaderIcon(systemImage: "bubble.left.and.text.bubble.right")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chat history")
        .accessibilityHint("Opens your conversations with Cove")
    }

    /// Animates the swap itself rather than leaning on an `.animation(value:)`
    /// higher up, so the row cannot end up animating twice.
    private func toggleSearch() {
        CoveHaptics.selection()

        if isSearchPresented {
            isFieldFocused = false
            query = ""
            withAnimation(reduceMotion ? nil : Self.morph) {
                isSearchPresented = false
            }
        } else {
            withAnimation(reduceMotion ? nil : Self.morph) {
                isSearchPresented = true
            }
            Task { @MainActor in
                await Task.yield()
                isFieldFocused = true
            }
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
                    // Clears the text and stays open. Closing search from here
                    // meant the only way to delete a word was to lose the field
                    // and start again.
                    query = ""
                    isFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(CoveTheme.ink.opacity(0.35))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        // Takes the row the count pill and title used to share, so the field is
        // full width rather than shrunk to its placeholder.
        .frame(maxWidth: .infinity)
        // Matches `CoveHeaderIcon`, so opening search cannot change the
        // header's height and nothing below it moves.
        .frame(height: 36)
        .glassEffect(.regular.interactive(), in: Capsule())
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

    /// A pull asks Photos for anything new, then refreshes every saved vector.
    /// The model actor is polled only for its coarse busy state so the system
    /// refresh control and Cove shimmer finish with the actual indexing work.
    private func refreshShelf() async {
        guard !isRefreshingShelf else { return }
        isRefreshingShelf = true
        CoveHaptics.impact(.medium)
        defer {
            isRefreshingShelf = false
            CoveHaptics.success()
        }

        await importer.importLibrary()
        _ = await ShelfProcessor.shared.reindexEmbeddings()

        while await ShelfProcessor.shared.isBusy {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(140))
        }

        await categorizer.prepareIfNeeded()
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CoveTheme.ink)

            VStack(spacing: 8) {
                Text("Nothing saved yet")
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

/// The Home title doubles as the refresh indicator: it grows with elastic
/// overscroll, then a highlight travels through the letters while Cove updates
/// the photo library and its semantic index.
private struct CoveRefreshingTitle: View {
    let pullDistance: CGFloat
    let isRefreshing: Bool

    private var title: some View {
        Text("Cove")
            .font(.system(.title2, design: .serif, weight: .semibold))
    }

    var body: some View {
        title
            .foregroundStyle(CoveTheme.ink.opacity(isRefreshing ? 0.58 : 1))
            .coveShimmer(isActive: isRefreshing)
            .scaleEffect(
                isRefreshing
                    ? 1.18
                    : 1 + min(pullDistance / 420, 0.24)
            )
            .animation(.snappy(duration: 0.2), value: pullDistance)
            .animation(.spring(response: 0.34, dampingFraction: 0.72), value: isRefreshing)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Empty home") {
    ShelfView()
        .modelContainer(for: [ShelfItem.self, ChatThread.self], inMemory: true)
        .environment(\.aiServices, .mock)
}
