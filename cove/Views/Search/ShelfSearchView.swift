import SwiftData
import SwiftUI

struct ShelfSearchView: View {
    @Environment(\.aiServices) private var aiServices
    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]

    @State private var query = ""
    @State private var results: [ShelfItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 156), spacing: 14)]

    var body: some View {
        ZStack {
            CoveInkBackground()
            content
        }
        .navigationTitle("Search")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by meaning")
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
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "Nothing to search yet",
                    systemImage: "sparkle.magnifyingglass",
                    description: Text("Add your first item, then search it by title, note, or extracted text.")
                )
            } else if results.isEmpty, !query.isEmpty, !isSearching {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Hybrid semantic + keyword search · on device", systemImage: "cpu")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(results) { item in
                                NavigationLink {
                                    ItemDetailView(item: item)
                                } label: {
                                    ShelfCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(16)
                }
                .overlay {
                    if isSearching {
                        ProgressView("Searching on device…")
                            .padding(18)
                            .glassEffect(.regular, in: .rect(cornerRadius: 18))
                    }
                }
            }
        }
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
