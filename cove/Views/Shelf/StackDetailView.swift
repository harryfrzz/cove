import SwiftUI

/// Every item inside one stack (a category bucket or "All"), laid out as
/// the masonry wall.
struct StackDetailView: View {
    let title: String
    let items: [ShelfItem]
    /// Tapped pile's frame in global space; the wall scatters out from it.
    var scatterFrame: CGRect? = nil

    /// `nil` until a long press starts a selection.
    @State private var selection: Set<UUID>?

    var body: some View {
        ZStack {
            CoveInkBackground()

            ScrollView {
                MasonryWall(
                    items: items,
                    scattersIn: true,
                    scatterFrame: scatterFrame,
                    selection: $selection
                )
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            if selection != nil {
                SelectionActionBar(selection: $selection, items: items)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.28), value: selection == nil)
        .navigationTitle(selection == nil ? title : "")
        .navigationBarTitleDisplayMode(.inline)
        // Leaving the screen shouldn't strand it in selection mode.
        .onDisappear { selection = nil }
    }
}
