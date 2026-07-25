import SwiftData
import SwiftUI

struct ShelfSearchView: View {
    @Environment(\.aiServices) private var aiServices
    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]

    @State private var query = ""
    @State private var results: [ShelfItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ZStack {
            CoveInkBackground()
            content
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: query) {
            await performSearch()
        }
        .onAppear {
            if results.isEmpty { results = items }
        }
        .alert("Search failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            emptyLibrary
        } else {
            ScrollView {
                if results.isEmpty, !query.isEmpty, !isSearching {
                    noMatches
                        .padding(.top, 80)
                } else {
                    MasonryWall(items: results)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            // Bar (not a plain inset) so cards scrolling underneath get the
            // system's own progressive blur, like the shelf page.
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

    // MARK: - Chrome

    private var topBar: some View {
        VStack(spacing: 12) {
            Text("Search")
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(CoveTheme.ink)
                .frame(maxWidth: .infinity)

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

    // MARK: - Empty states

    private var emptyLibrary: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 48, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CoveTheme.ink)

            VStack(spacing: 8) {
                Text("Nothing to search yet")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(CoveTheme.ink)
                Text("Add your first item, then search it\nby title, note, or extracted text.")
                    .font(.subheadline)
                    .foregroundStyle(CoveTheme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 36)
        .padding(.horizontal, 30)
        .glassEffect(.regular, in: .rect(cornerRadius: 34))
        .padding(36)
        .accessibilityElement(children: .combine)
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

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func performSearch() async {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = items
            isSearching = false
            return
        }

        do {
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
}
