import SwiftUI

/// Home wall of category stacks: an "All" pile first, then one pile per
/// non-empty bucket. Two-column masonry — each pile keeps its front cover's
/// real aspect ratio and goes to the currently shortest column, exactly like
/// the item wall. Tapping a pile opens the full masonry wall for that group.
struct CategoryStackGrid: View {
    let items: [ShelfItem]
    let groups: [(bucket: ShelfBucket, items: [ShelfItem])]

    private static let columnCount = 2
    private static let spacing: CGFloat = 18
    private static let rowSpacing: CGFloat = 22
    /// Label row's estimated height contribution, as a fraction of column
    /// width, used only for packing.
    private static let labelAspect: CGFloat = 0.22

    private struct StackSpec: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let tint: Color
        let items: [ShelfItem]
    }

    var body: some View {
        let columns = distributedColumns()

        HStack(alignment: .top, spacing: Self.spacing) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                LazyVStack(spacing: Self.rowSpacing) {
                    ForEach(column) { spec in
                        NavigationLink {
                            StackDetailView(title: spec.title, items: spec.items)
                        } label: {
                            CategoryStackCard(
                                title: spec.title,
                                systemImage: spec.systemImage,
                                tint: spec.tint,
                                items: spec.items
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var allStacks: [StackSpec] {
        var stacks = [
            StackSpec(
                id: "all",
                title: "All",
                systemImage: "square.grid.2x2",
                tint: .orange,
                items: items
            )
        ]
        stacks.append(contentsOf: groups.map { group in
            StackSpec(
                id: group.bucket.rawValue,
                title: group.bucket.label,
                systemImage: group.bucket.systemImage,
                tint: group.bucket.tint,
                items: group.items
            )
        })
        return stacks
    }

    /// Shortest-column-first packing, mirroring the item wall, so piles with
    /// different cover heights stagger instead of leaving row-sized gaps.
    private func distributedColumns() -> [[StackSpec]] {
        var columns: [[StackSpec]] = Array(repeating: [], count: Self.columnCount)
        var heights = [CGFloat](repeating: 0, count: Self.columnCount)

        for spec in allStacks {
            let shortest = heights.enumerated().min { $0.element < $1.element }?.offset ?? 0
            columns[shortest].append(spec)
            heights[shortest] += CategoryStackCard.pileAspect(of: spec.items) + Self.labelAspect
        }
        return columns
    }
}

/// One pile in the wall: up to three layered cover images (tilted slightly,
/// newest on top) at the front cover's real proportions, with the stack's
/// name and count centered underneath.
private struct CategoryStackCard: View {
    let title: String
    let systemImage: String
    let tint: Color
    let items: [ShelfItem]

    /// Newest items that actually have an image, front layer first.
    private var covers: [ShelfItem] {
        Array(items.lazy.filter { $0.imageData != nil }.prefix(3))
    }

    /// Height/width of the front cover — the pile keeps the image's real
    /// proportions, exactly like the masonry wall. Safety clamp only.
    /// Static so the grid can reuse it for column packing.
    static func pileAspect(of items: [ShelfItem]) -> CGFloat {
        guard let front = items.first(where: { $0.imageData != nil }) else { return 1 }
        let ratio = ThumbnailStore.aspectRatio(
            id: front.id,
            data: front.imageData,
            fallback: 1
        )
        return min(max(ratio, 0.35), 3.0)
    }

    var body: some View {
        VStack(spacing: 12) {
            pile
                .aspectRatio(1 / Self.pileAspect(of: items), contentMode: .fit)
                // Air for the tilted back sheets peeking past the cover.
                .padding(.horizontal, 8)
                .padding(.top, 6)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(.callout, design: .serif, weight: .semibold))
                    .foregroundStyle(CoveTheme.ink)
                    .lineLimit(1)
                Text("\(items.count)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(CoveTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(items.count) items")
    }

    private var pile: some View {
        ZStack {
            if covers.isEmpty {
                placeholderLayer
            } else {
                // Back-to-front so the newest cover draws on top. Back
                // sheets stay full size and just tilt, so their corners
                // peek out past the cover like a pile of prints.
                ForEach(Array(covers.enumerated().reversed()), id: \.offset) { depth, item in
                    coverLayer(for: item)
                        .rotationEffect(rotation(at: depth))
                }
            }
        }
    }

    private func coverLayer(for item: ShelfItem) -> some View {
        ShelfThumbnail(item: item)
            .clipShape(.rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
    }

    private var placeholderLayer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.42), tint.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(CoveTheme.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
    }

    /// Depth 0 is the front card; deeper layers tilt alternately so both
    /// sides of the pile show a peeking corner.
    private func rotation(at depth: Int) -> Angle {
        switch depth {
        case 1: .degrees(-4.5)
        case 2: .degrees(4)
        default: .zero
        }
    }
}
