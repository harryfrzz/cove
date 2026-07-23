import SwiftUI

/// Every item inside one stack (a category bucket or "All"), laid out as
/// the masonry wall.
struct StackDetailView: View {
    let title: String
    let items: [ShelfItem]

    var body: some View {
        ZStack {
            CoveInkBackground()

            ScrollView {
                MasonryWall(items: items)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
