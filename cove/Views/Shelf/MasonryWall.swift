import SwiftUI

/// Staggered wall of item cards. Each item goes to the currently shortest
/// column, using the image's real aspect ratio (read once from the file
/// header, cached) so packing matches rendering exactly and mixed
/// screenshot heights fill in without gaps.
struct MasonryWall: View {
    let items: [ShelfItem]

    private static let columnCount = 3
    private static let spacing: CGFloat = 12
    /// Safety bounds only — cards keep the image's real proportions, so a
    /// full-height screenshot renders at its true aspect. The clamp just
    /// guards degenerate files (extreme panoramas, corrupt headers).
    private static let aspectRange: ClosedRange<CGFloat> = 0.35...3.0
    /// Packing estimate for image-less (text/link) cards.
    private static let textCardAspect: CGFloat = 0.62

    @State private var wallWidth: CGFloat = 0

    var body: some View {
        let columnWidth = (wallWidth - Self.spacing * CGFloat(Self.columnCount - 1)) / CGFloat(Self.columnCount)

        HStack(alignment: .top, spacing: Self.spacing) {
            if columnWidth > 0 {
                ForEach(Array(distributedColumns().enumerated()), id: \.offset) { _, column in
                    LazyVStack(spacing: Self.spacing) {
                        ForEach(column, id: \.id) { item in
                            NavigationLink {
                                ItemDetailView(item: item)
                            } label: {
                                MasonryCard(
                                    item: item,
                                    width: columnWidth,
                                    aspect: Self.cardAspect(of: item)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: columnWidth)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            wallWidth = newWidth
        }
    }

    /// Clamped card height/width used for both packing and layout.
    /// Returns nil for cards without an image (their height is intrinsic).
    private static func cardAspect(of item: ShelfItem) -> CGFloat? {
        guard item.imageData != nil else { return nil }
        let ratio = ThumbnailStore.aspectRatio(
            id: item.id,
            data: item.imageData,
            fallback: 1.2
        )
        return min(max(ratio, aspectRange.lowerBound), aspectRange.upperBound)
    }

    private func distributedColumns() -> [[ShelfItem]] {
        var columns: [[ShelfItem]] = Array(repeating: [], count: Self.columnCount)
        var heights = [CGFloat](repeating: 0, count: Self.columnCount)
        let spacingRatio = Self.spacing / max(wallWidth / CGFloat(Self.columnCount), 1)

        for item in items {
            let shortest = heights.enumerated().min { $0.element < $1.element }?.offset ?? 0
            columns[shortest].append(item)
            heights[shortest] += (Self.cardAspect(of: item) ?? Self.textCardAspect) + spacingRatio
        }
        return columns
    }
}

private struct MasonryCard: View {
    let item: ShelfItem
    let width: CGFloat
    /// Clamped height/width ratio for image cards; nil for text cards.
    let aspect: CGFloat?

    var body: some View {
        Group {
            if item.imageData != nil, let aspect {
                ShelfThumbnail(item: item)
                    .frame(width: width, height: (width * aspect).rounded())
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: item.kind.systemImage)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(CoveTheme.ink.opacity(0.6))
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CoveTheme.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                    if let note = item.userNote, !note.isEmpty {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(CoveTheme.inkSecondary)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.white.opacity(0.65))
            }
        }
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(CoveTheme.hairline, lineWidth: 1)
        }
        .overlay {
            if item.processingState == .processing || item.processingState == .queued {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                ProgressView()
                    .controlSize(.small)
            }
        }
        .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
        .accessibilityLabel(item.title)
    }
}
