import SwiftData
import SwiftUI

/// Landing dashboard: a glanceable overview of everything Cove has captured —
/// counts, wallet passes, upcoming events, and the latest saves — with jump
/// links into the deeper tabs. Cards share the masonry wall's paper style
/// (soft white, hairline, gentle shadow) so the page reads as one album.
struct HomeDashboardView: View {
    /// Wired by the shell so tiles can jump straight to the matching tab.
    var onOpenShelf: () -> Void = {}
    var onOpenWallet: () -> Void = {}

    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]
    @State private var categorizer = ShelfCategorizer.shared

    /// Tapped pass, held alone over the blurred page.
    @State private var expandedCard: WalletCard?
    /// Zoom sources: passes grow out of the fan, prints out of the strip —
    /// the same opening the album piles use.
    @Namespace private var passNamespace
    @Namespace private var printNamespace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !walletCards.isEmpty {
                    walletSection
                }

                statGrid

                if !eventRows.isEmpty {
                    eventsSection
                }

                if !recentItems.isEmpty {
                    recentSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
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
        .background(CoveInkBackground())
        .toolbar(.hidden, for: .navigationBar)
        // Full-screen (not a sheet) with a clear presentation background, so
        // the dashboard — dock included — stays behind the pass and is what
        // the blur actually blurs.
        .fullScreenCover(item: $expandedCard) { card in
            WalletPassDetailView(card: card)
                .navigationTransition(.zoom(sourceID: card.id, in: passNamespace))
                .presentationBackground(.clear)
        }
    }

    // MARK: - Derived data

    private var readyItems: [ShelfItem] {
        items.filter { $0.processingState == .ready }
    }

    private var walletCards: [WalletCard] {
        readyItems
            .filter { item in
                if item.isInWallet { return true }
                let bucket = categorizer.bucket(for: item)
                return bucket == .receipts || bucket == .events
            }
            .prefix(6)
            .map { WalletCard.card(for: $0) }
    }

    /// Event/ticket rows, soonest upcoming first when a date parses, else the
    /// latest captures. Extraction dates are freeform strings, so parsing is
    /// best-effort via the system date detector.
    private var eventRows: [EventRow] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

        let rows: [EventRow] = readyItems.compactMap { item in
            guard let extraction = item.extraction else { return nil }

            let (title, when, place): (String?, String?, String?) =
                switch extraction.category {
                case "event":
                    (extraction.eventTitle, extraction.eventStart, extraction.eventLocation)
                case "ticket":
                    (extraction.ticketTitle, extraction.ticketDateTime, extraction.venueOrOperator)
                default:
                    (nil, nil, nil)
                }
            guard let title else { return nil }

            var parsed: Date?
            if let when, let detector {
                let range = NSRange(when.startIndex..., in: when)
                parsed = detector.firstMatch(in: when, range: range)?.date
            }
            return EventRow(
                id: item.id,
                title: title,
                when: when,
                place: place,
                date: parsed,
                item: item
            )
        }

        let upcoming = rows
            .filter { ($0.date ?? .distantPast) >= .now }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        if !upcoming.isEmpty { return Array(upcoming.prefix(4)) }
        return Array(rows.prefix(4))
    }

    private var recentItems: [ShelfItem] {
        Array(items.prefix(8))
    }

    private func count(of bucket: ShelfBucket) -> Int {
        readyItems.count { categorizer.bucket(for: $0) == bucket }
    }

    // MARK: - Chrome

    /// Same shape as the shelf top bar: centered wordmark, orange item count
    /// on the trailing side.
    private var topBar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)

            Text("\(items.count)")
                .font(.system(.subheadline, design: .serif, weight: .bold))
                .foregroundStyle(.orange)
                .frame(minWidth: 36, minHeight: 36)
                .glassEffect(.regular, in: Circle())
                .accessibilityLabel("\(items.count) items")
        }
        .overlay {
            Text("Cove")
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(CoveTheme.ink)
        }
    }

    // MARK: - Stats

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            StatTile(
                value: items.count,
                label: "Items saved",
                systemImage: "square.stack.3d.up",
                tint: CoveTheme.ink,
                action: onOpenShelf
            )
            StatTile(
                value: walletCards.count,
                label: "Wallet passes",
                systemImage: "wallet.pass",
                tint: .orange,
                action: onOpenWallet
            )
            StatTile(
                value: count(of: .receipts),
                label: "Receipts",
                systemImage: "receipt",
                tint: ShelfBucket.receipts.tint,
                action: onOpenWallet
            )
            StatTile(
                value: count(of: .events),
                label: "Events & tickets",
                systemImage: "ticket",
                tint: ShelfBucket.events.tint,
                action: onOpenWallet
            )
        }
    }

    // MARK: - Wallet preview

    private var walletSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Wallet", actionTitle: "Open wallet", action: onOpenWallet)

            WalletFanStack(
                cards: walletCards,
                namespace: passNamespace,
                onSelect: { expandedCard = $0 }
            )
        }
    }

    // MARK: - Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(hasUpcoming ? "Upcoming" : "Events & tickets")

            VStack(spacing: 10) {
                ForEach(eventRows) { row in
                    NavigationLink {
                        ItemDetailView(item: row.item)
                    } label: {
                        EventRowView(row: row)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var hasUpcoming: Bool {
        eventRows.contains { ($0.date ?? .distantPast) >= .now }
    }

    // MARK: - Recents

    /// Latest captures as a loose photo strip — small paper cards leaning
    /// like prints on a shelf, echoing the masonry wall.
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Recently saved", actionTitle: "See shelf", action: onOpenShelf)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .bottom, spacing: 12) {
                    ForEach(Array(recentItems.enumerated()), id: \.element.id) { index, item in
                        NavigationLink {
                            ItemDetailView(item: item)
                                .navigationTransition(
                                    .zoom(sourceID: item.id, in: printNamespace)
                                )
                        } label: {
                            RecentPrintCard(item: item)
                                .rotationEffect(.degrees(index.isMultiple(of: 2) ? -1.6 : 1.4))
                        }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: item.id, in: printNamespace)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    // MARK: - Shared chrome

    private func sectionHeader(
        _ title: String,
        actionTitle: String? = nil,
        action: @escaping () -> Void = {}
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(CoveTheme.ink)
            Spacer()
            if let actionTitle {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(CoveTheme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Paper card style

/// The masonry wall's card finish: soft white paper, hairline edge, gentle
/// lift. Shared by every dashboard card so the page matches the shelf.
private struct PaperCard: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(.white.opacity(0.65))
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(CoveTheme.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
    }
}

private extension View {
    func paperCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(PaperCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Stat tile

private struct StatTile: View {
    let value: Int
    let label: String
    let systemImage: String
    let tint: Color
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(value)")
                        .font(.system(.title, design: .serif, weight: .bold))
                        .foregroundStyle(CoveTheme.ink)
                        .contentTransition(.numericText())
                    Text(label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CoveTheme.inkSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .paperCard(cornerRadius: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value) \(label)")
    }
}

// MARK: - Event row

private struct EventRow: Identifiable {
    let id: UUID
    let title: String
    let when: String?
    let place: String?
    let date: Date?
    let item: ShelfItem
}

private struct EventRowView: View {
    let row: EventRow

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                if let date = row.date {
                    Text(date.formatted(.dateTime.day()))
                        .font(.system(.title3, design: .serif, weight: .bold))
                        .foregroundStyle(CoveTheme.ink)
                    Text(date.formatted(.dateTime.month(.abbreviated)))
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(ShelfBucket.events.tint)
                } else {
                    Image(systemName: "ticket")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(ShelfBucket.events.tint)
                }
            }
            .frame(width: 44, height: 44)
            .background(ShelfBucket.events.tint.opacity(0.12), in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CoveTheme.ink)
                    .lineLimit(1)
                Text([row.when, row.place].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(CoveTheme.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CoveTheme.inkSecondary)
        }
        .padding(12)
        .paperCard()
    }
}

// MARK: - Wallet fan stack

/// Most recent passes fanned like a hand of cards: the newest sits in front
/// at the bottom, older ones peek out above it, each tilted a touch the
/// other way.
private struct WalletFanStack: View {
    let cards: [WalletCard]
    let namespace: Namespace.ID
    let onSelect: (WalletCard) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flipped once on appear; the bob is a repeating autoreversing
    /// animation driven off this single change.
    @State private var breathing = false

    private static let cardHeight: CGFloat = 212
    private static let peek: CGFloat = 66
    private static let maxCards = 4
    /// Headroom above and below the fan so the drifting cards never clip.
    private static let bobRoom: CGFloat = 10

    private var shown: [WalletCard] { Array(cards.prefix(Self.maxCards)) }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Order 0 is the newest pass; it draws in front and sits lowest.
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, card in
                Button {
                    onSelect(card)
                } label: {
                    WalletCardView(card: card)
                }
                .buttonStyle(.plain)
                .scaleEffect(1 - CGFloat(index) * 0.015)
                .rotationEffect(Self.tilt(order: index), anchor: .center)
                .offset(y: -CGFloat(index) * Self.peek)
                // Idle drift, applied after the fan offset so the resting
                // layout is untouched.
                .offset(y: bob(order: index))
                .animation(bobAnimation(order: index), value: breathing)
                .matchedTransitionSource(id: card.id, in: namespace)
                .zIndex(-Double(index))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(
            height: Self.cardHeight + CGFloat(max(shown.count - 1, 0)) * Self.peek + 14,
            alignment: .bottom
        )
        .padding(.horizontal, 6)
        .padding(.top, 4 + Self.bobRoom)
        .padding(.bottom, 8 + Self.bobRoom)
        .onAppear { breathing = true }
    }

    /// Neighbours drift opposite ways, so the fan slowly opens and closes
    /// instead of sliding as one block. Deeper cards travel a little further
    /// — the parallax reads as depth.
    private func bob(order: Int) -> CGFloat {
        guard !reduceMotion else { return 0 }
        let amplitude = 3.5 + CGFloat(order) * 1.4
        let up = order.isMultiple(of: 2)
        return (breathing == up) ? -amplitude : amplitude
    }

    /// Slightly different periods per card, so the cards never sync up into
    /// one pulsing shape.
    private func bobAnimation(order: Int) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: 2.4 + Double(order) * 0.45)
            .repeatForever(autoreverses: true)
            .delay(Double(order) * 0.15)
    }

    /// Alternating fan tilts, front card nearly straight — same spirit as
    /// the shelf pile (see MasonryWall.heapTilt).
    private static func tilt(order: Int) -> Angle {
        switch order {
        case 0: .degrees(-1.5)
        case 1: .degrees(2.8)
        case 2: .degrees(-3.4)
        case 3: .degrees(3.2)
        default: .degrees(-2.6)
        }
    }
}

// MARK: - Recent print card

/// A small "print": thumbnail with a paper caption strip, like a photo
/// pulled off the masonry wall.
private struct RecentPrintCard: View {
    let item: ShelfItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if item.imageData != nil {
                    ShelfThumbnail(item: item)
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: item.kind.systemImage)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(CoveTheme.ink.opacity(0.55))
                        Text(item.kind.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(CoveTheme.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CoveTheme.ink.opacity(0.05))
                }
            }
            .frame(width: 118, height: 132)
            .clipped()
            .overlay {
                if item.processingState == .queued || item.processingState == .processing {
                    Rectangle().fill(.ultraThinMaterial)
                    ProgressView().controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CoveTheme.ink)
                    .lineLimit(1)
                Text(item.createdAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(CoveTheme.inkSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(width: 118, alignment: .leading)
        }
        .paperCard(cornerRadius: 14)
        .accessibilityLabel(item.title)
    }
}

#Preview {
    NavigationStack {
        HomeDashboardView()
    }
    .modelContainer(for: ShelfItem.self, inMemory: true)
    .environment(\.aiServices, .mock)
}
