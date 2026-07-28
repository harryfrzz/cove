import SwiftData
import SwiftUI

/// Bottom bar for multi-select on the masonry wall: how many are picked, a way
/// out, and the destructive action.
///
/// Lives in the hosting screen rather than in `MasonryWall` because the wall
/// sits inside a `ScrollView` — an overlay there would scroll away with the
/// cards instead of staying under the thumb.
struct SelectionActionBar: View {
    /// `nil` when not selecting. Writing `nil` leaves selection mode.
    @Binding var selection: Set<UUID>?
    /// Everything currently on screen, so "Select all" knows the full set.
    let items: [ShelfItem]

    @Environment(\.modelContext) private var modelContext
    @State private var isConfirming = false

    private var count: Int { selection?.count ?? 0 }

    var body: some View {
        HStack(spacing: 14) {
            Button("Done") {
                selection = nil
            }
            .font(.subheadline.weight(.semibold))

            Spacer(minLength: 0)

            Text(count == 0 ? "Select items" : "\(count) selected")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CoveTheme.inkSecondary)
                .contentTransition(.numericText())

            Spacer(minLength: 0)

            Button(allSelected ? "None" : "All") {
                selection = allSelected ? [] : Set(items.map(\.id))
            }
            .font(.subheadline.weight(.medium))

            Button(role: .destructive) {
                isConfirming = true
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(count == 0)
            .accessibilityLabel("Delete \(count) selected")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 20)
        .animation(.smooth(duration: 0.25), value: count)
        .confirmationDialog(
            count == 1 ? "Delete 1 item?" : "Delete \(count) items?",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: deleteSelected)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removed from this device for good. This can't be undone.")
        }
    }

    private var allSelected: Bool {
        guard let selection, !items.isEmpty else { return false }
        return selection.count == items.count
    }

    private func deleteSelected() {
        guard let ids = selection else { return }
        modelContext.deleteShelfItems(items.filter { ids.contains($0.id) })
        // Straight out of selection mode: staying in it with an empty set and a
        // now-shorter wall reads as though the delete didn't take.
        selection = nil
    }
}
