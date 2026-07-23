import SwiftUI

/// Every item inside one stack (a category bucket or "All"), laid out as
/// the masonry wall.
struct StackDetailView: View {
    let title: String
    let items: [ShelfItem]
    /// Tapped pile's frame in global space; the wall scatters out from it.
    var scatterFrame: CGRect? = nil

    var body: some View {
        ZStack {
            CoveInkBackground()

            ScrollView {
                MasonryWall(items: items, scattersIn: true, scatterFrame: scatterFrame)
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
