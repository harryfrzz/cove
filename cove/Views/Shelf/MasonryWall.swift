import SwiftUI

/// Staggered wall of item cards. Each item goes to the currently shortest
/// column, using the image's real aspect ratio (read once from the file
/// header, cached) so packing matches rendering exactly and mixed
/// screenshot heights fill in without gaps.
struct MasonryWall: View {
    let items: [ShelfItem]
    /// When true, cards start heaped at the origin below (like the stack
    /// they came from) and spring outward into their slots on appear.
    var scattersIn: Bool = false
    /// Global-space frame of the tapped pile on the previous screen: the
    /// heap gathers at its center, sized to match it. Defaults to the
    /// wall's top center.
    var scatterFrame: CGRect? = nil
    /// Multi-select state, owned by the hosting screen so its action bar can
    /// sit outside the scroll view. `nil` means "not selecting"; a long press
    /// or the context menu starts it. Defaults to a constant, so a caller that
    /// doesn't opt in simply never enters selection mode.
    var selection: Binding<Set<UUID>?> = .constant(nil)

    private static let columnCount = 3
    private static let spacing: CGFloat = 12
    /// Safety bounds only — cards keep the image's real proportions, so a
    /// full-height screenshot renders at its true aspect. The clamp just
    /// guards degenerate files (extreme panoramas, corrupt headers).
    private static let aspectRange: ClosedRange<CGFloat> = 0.35...3.0
    /// Packing estimate for image-less (text/link) cards.
    private static let textCardAspect: CGFloat = 0.62

    /// Wall frame in global space; width drives layout, origin anchors the
    /// scatter heap.
    @State private var wallFrame: CGRect = .zero
    @State private var settled = false
    /// Items awaiting confirmation from the card context menu.
    @State private var pendingDelete: [ShelfItem] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    /// Zoom source for opening one card, mirroring how a pile opens into its
    /// wall — the card grows out of its slot instead of sliding in.
    @Namespace private var cardNamespace

    private var wallWidth: CGFloat { wallFrame.width }

    private struct PlacedItem: Identifiable {
        let item: ShelfItem
        /// Packing order across the whole wall; staggers the scatter.
        let order: Int
        /// Vector from the card's slot back to the pile origin.
        let delta: CGSize
        var id: UUID { item.id }
    }

    var body: some View {
        let columnWidth = (wallWidth - Self.spacing * CGFloat(Self.columnCount - 1)) / CGFloat(Self.columnCount)

        HStack(alignment: .top, spacing: Self.spacing) {
            if columnWidth > 0 {
                ForEach(Array(distributedColumns(columnWidth: columnWidth).enumerated()), id: \.offset) { _, column in
                    LazyVStack(spacing: Self.spacing) {
                        ForEach(column) { placed in
                            cardCell(placed, columnWidth: columnWidth)
                            .modifier(
                                ScatterEffect(
                                    isScattered: !scattersIn || settled || reduceMotion,
                                    delta: placed.delta,
                                    heapScale: heapScale(columnWidth: columnWidth),
                                    tilt: Self.heapTilt(order: placed.order),
                                    delay: min(Double(placed.order) * 0.03, 0.36)
                                )
                            )
                            // Outside the scatter so the zoom source is the
                            // card's settled frame, not its heaped transform.
                            .matchedTransitionSource(id: placed.id, in: cardNamespace)
                            .contextMenu {
                                Button("Select", systemImage: "checkmark.circle") {
                                    selection.wrappedValue = [placed.id]
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    pendingDelete = [placed.item]
                                }
                            }
                            // Heap stacks like the pile: the newest card
                            // (the pile's front cover) draws on top and is
                            // also the first to fly into place.
                            .zIndex(-Double(placed.order))
                        }
                    }
                    .frame(width: columnWidth)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { newFrame in
            wallFrame = newFrame
        }
        .task {
            guard scattersIn, !settled else { return }
            // One committed frame with the cards heaped, then release so
            // the burst plays together with the zoom-in.
            try? await Task.sleep(for: .milliseconds(50))
            settled = true
        }
        .confirmationDialog(
            "Delete this item?",
            isPresented: .init(
                get: { !pendingDelete.isEmpty },
                set: { if !$0 { pendingDelete = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.deleteShelfItems(pendingDelete)
                pendingDelete = []
            }
            Button("Cancel", role: .cancel) { pendingDelete = [] }
        } message: {
            Text("Removed from this device for good.")
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

    /// One card: a link when browsing, a selection toggle when selecting.
    @ViewBuilder
    private func cardCell(_ placed: PlacedItem, columnWidth: CGFloat) -> some View {
        let selecting = selection.wrappedValue != nil
        let isOn = selection.wrappedValue?.contains(placed.id) ?? false

        if selecting {
            Button {
                toggle(placed.id)
            } label: {
                face(placed, columnWidth: columnWidth, isSelected: isOn)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                ItemDetailView(item: placed.item)
                    .navigationTransition(
                        .zoom(sourceID: placed.id, in: cardNamespace)
                    )
            } label: {
                face(placed, columnWidth: columnWidth, isSelected: false)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture().onEnded {
                    CoveHaptics.impact(.soft)
                }
            )
            // Long press is the standard way into multi-select, and it's how
            // people already expect to start one in Photos.
            .onLongPressGesture {
                CoveHaptics.impact(.medium)
                selection.wrappedValue = [placed.id]
            }
        }
    }

    private func face(_ placed: PlacedItem, columnWidth: CGFloat, isSelected: Bool) -> some View {
        MasonryCard(
            item: placed.item,
            width: columnWidth,
            aspect: Self.cardAspect(of: placed.item)
        )
        // Dim the unpicked ones rather than only marking the picked ones —
        // at a glance the selection should read as the bright subset.
        .opacity(selection.wrappedValue == nil || isSelected ? 1 : 0.55)
        .overlay(alignment: .topTrailing) {
            if selection.wrappedValue != nil {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? Color.accentColor : .black.opacity(0.35))
                    .shadow(color: .black.opacity(0.3), radius: 3)
                    .padding(8)
            }
        }
    }

    private func toggle(_ id: UUID) {
        CoveHaptics.selection()
        var current = selection.wrappedValue ?? []
        if current.contains(id) {
            current.remove(id)
        } else {
            current.insert(id)
        }
        selection.wrappedValue = current
    }

    /// Heaped cards match the tapped pile's cover width (the pile pads its
    /// cover 8pt each side), so the heap looks like the album item itself.
    private func heapScale(columnWidth: CGFloat) -> CGFloat {
        guard let scatterFrame, columnWidth > 0 else { return 0.72 }
        let coverWidth = scatterFrame.width - 16
        return min(max(coverWidth / columnWidth, 0.5), 2.5)
    }

    /// Heap tilts mirror the album pile exactly (see CategoryStackCard):
    /// front card straight, back sheets at the same alternating angles, so
    /// the heap is indistinguishable from the tapped pile.
    private static func heapTilt(order: Int) -> Angle {
        switch order {
        case 0: .zero
        case 1: .degrees(-4.5)
        case 2: .degrees(4)
        default: order.isMultiple(of: 2) ? .degrees(4) : .degrees(-4.5)
        }
    }

    private func distributedColumns(columnWidth: CGFloat) -> [[PlacedItem]] {
        var columns: [[PlacedItem]] = Array(repeating: [], count: Self.columnCount)
        var heights = [CGFloat](repeating: 0, count: Self.columnCount)
        let spacingRatio = Self.spacing / max(columnWidth, 1)

        // Heap point in the wall's own space: the tapped pile's cover
        // center (converted from global; the pile cell carries a 6pt top
        // inset and a ~32pt label strip below the cover), or the wall's
        // top center as a fallback.
        let origin: CGPoint
        if let scatterFrame, wallFrame != .zero {
            let coverMidY = scatterFrame.minY + 6 + (scatterFrame.height - 6 - 32) / 2
            origin = CGPoint(
                x: scatterFrame.midX - wallFrame.minX,
                y: coverMidY - wallFrame.minY
            )
        } else {
            origin = CGPoint(x: wallWidth / 2, y: -24)
        }

        for (order, item) in items.enumerated() {
            let shortest = heights.enumerated().min { $0.element < $1.element }?.offset ?? 0

            // Vector from this card's slot center back to the heap point.
            let cardHeight = (Self.cardAspect(of: item) ?? Self.textCardAspect) * columnWidth
            let slotCenter = CGPoint(
                x: CGFloat(shortest) * (columnWidth + Self.spacing) + columnWidth / 2,
                y: heights[shortest] * columnWidth + cardHeight / 2
            )
            let delta = CGSize(
                width: origin.x - slotCenter.x,
                height: origin.y - slotCenter.y
            )

            columns[shortest].append(PlacedItem(item: item, order: order, delta: delta))
            heights[shortest] += (Self.cardAspect(of: item) ?? Self.textCardAspect) + spacingRatio
        }
        return columns
    }
}

/// Heaped-pile state for one card: pulled back to the wall's origin, tilted
/// and shrunk; springs into place (offset/tilt/scale all zero out) once
/// `isScattered` flips.
private struct ScatterEffect: ViewModifier {
    let isScattered: Bool
    let delta: CGSize
    let heapScale: CGFloat
    let tilt: Angle
    let delay: Double

    func body(content: Content) -> some View {
        content
            .scaleEffect(isScattered ? 1 : heapScale)
            .rotationEffect(isScattered ? .zero : tilt)
            .offset(isScattered ? .zero : delta)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.78).delay(delay),
                value: isScattered
            )
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
