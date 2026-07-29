import SwiftData
import SwiftUI

/// Wallet destination built from the former Home ticket stack. The screenshots
/// library now owns Home, so this page is deliberately only about passes.
struct HomeDashboardView: View {
    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]
    /// Only for the empty state: a first launch spends its time indexing, and
    /// "nothing here yet" is the wrong thing to say while that is running.
    @State private var importer = GalleryImporter.shared

    /// Tapped pass, held alone over the blurred page.
    @State private var expandedCard: WalletCard?
    /// Passes grow out of the fan into their full-screen detail.
    @Namespace private var passNamespace

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if walletCards.isEmpty {
                    emptyState
                } else {
                    walletSection
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
            .filter(\.isWalletPass)
            .prefix(6)
            .map { WalletCard.card(for: $0) }
    }

    // MARK: - Empty state

    /// Defers to the indexer while it is running, then explains how a pass
    /// reaches the wallet rather than presenting an overview placeholder.
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: importer.isImporting ? "arrow.trianglehead.2.clockwise" : "sparkles")
                .font(.system(size: 34, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CoveTheme.ink.opacity(0.65))
                .symbolEffect(.pulse, isActive: importer.isImporting)

            Text(importer.isImporting ? "Reading your library" : "Your wallet is empty")
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(CoveTheme.ink)

            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(CoveTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if importer.isImporting, importer.totalCount > 0 {
                ProgressView(
                    value: Double(importer.importedCount),
                    total: Double(importer.totalCount)
                )
                .tint(CoveTheme.ink)
                .frame(maxWidth: 220)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 26)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .padding(.top, 40)
    }

    private var emptyMessage: String {
        if importer.isDenied {
            return "Cove has no access to your photos, so it cannot find passes yet. Capture one with the + button, or turn access on from Profile."
        }
        if importer.isImporting {
            return "Tickets, receipts, and passes will appear here as Cove finishes reading each screenshot."
        }
        return "Tickets and receipts appear here once Cove has read them. You can also add an item to Wallet from its detail page."
    }

    // MARK: - Chrome

    /// Named for the destination, not the app: the dock is icon-only, so every
    /// page's header has to say which tab you are standing on. The orange item
    /// count keeps its trailing slot.
    private var topBar: some View {
        CoveScreenHeader("Wallet") {
            Text("\(walletCards.count)")
                .font(.system(.subheadline, design: .serif, weight: .bold))
                .foregroundStyle(.orange)
                .frame(minWidth: 36, minHeight: 36)
                .glassEffect(.regular, in: Circle())
                .accessibilityLabel("\(walletCards.count) passes")
        }
    }

    // MARK: - Wallet

    private var walletSection: some View {
        WalletFanStack(
            cards: walletCards,
            namespace: passNamespace,
            onSelect: { expandedCard = $0 }
        )
    }
}

// MARK: - Wallet fan stack

/// Most recent passes stacked like a run of portrait admission tickets: the
/// newest sits in front at the bottom while the mastheads of older tickets
/// remain visible above it.
private struct WalletFanStack: View {
    let cards: [WalletCard]
    let namespace: Namespace.ID
    let onSelect: (WalletCard) -> Void

    /// Matches `HomeTicketCard` — the fan sizes its own container from this,
    /// so the two have to move together.
    private static let cardHeight: CGFloat = 510
    /// A real pile: the newest ticket sits in front at full height and the
    /// rest stack behind it, each showing just its emblem and category strip.
    /// Deliberately stops short of the title line — a half-clipped title reads
    /// as broken, an emblem strip reads as a stack.
    private static let peek: CGFloat = 42
    private static let maxCards = 3

    var body: some View {
        CoveCardDeck(
            cards: cards,
            cardHeight: Self.cardHeight,
            peek: Self.peek,
            maxCards: Self.maxCards,
            restingTilt: Self.tilt(order:),
            restingOffset: Self.fanOffset(order:),
            openActionName: "Open pass",
            namespace: namespace,
            onSelect: onSelect
        ) { card, _ in
            // Every depth draws the full ticket. A masthead-only placeholder
            // used to stand in at the rear, which is invisible at rest — only
            // the top strip shows — but the throw exposes that whole card on
            // its way past, so the pile flashed a blank pass and then popped
            // into a real one when it was promoted.
            HomeTicketCard(card: card, height: Self.cardHeight)
        }
    }

    /// The front ticket stays readable while the two mastheads behind it lean
    /// in opposite directions like a loose hand-stacked pile.
    private static func tilt(order: Int) -> Angle {
        switch order {
        case 0: .degrees(-0.35)
        case 1: .degrees(3.2)
        case 2: .degrees(-3.4)
        default: .zero
        }
    }

    /// A little horizontal separation makes both rear angles legible instead
    /// of leaving their corners perfectly superimposed.
    private static func fanOffset(order: Int) -> CGFloat {
        switch order {
        case 1: 5
        case 2: -5
        default: 0
        }
    }
}


// MARK: - Home portrait ticket

/// A Home-only pass face inspired by printed event stock: portrait proportions,
/// a field of registration marks, oversized type, a perforated stub, and a
/// machine-readable footer. The Wallet keeps its compact horizontal cards;
/// this one is allowed to behave like the page's editorial centrepiece.
private struct HomeTicketCard: View {
    let card: WalletCard
    let height: CGFloat

    private static let width: CGFloat = 318
    private static let stubHeight: CGFloat = 102
    private static let outline = HomeTicketShape(
        cornerRadius: 22,
        notchRadius: 12,
        stubHeight: stubHeight
    )

    var body: some View {
        VStack(spacing: 0) {
            mainBody
                .frame(maxHeight: .infinity)

            HomeTicketTearLine()
                .stroke(
                    style: StrokeStyle(
                        lineWidth: 1.2,
                        lineCap: .round,
                        dash: [4, 6]
                    )
                )
                .foregroundStyle(ink.opacity(0.48))
                .frame(height: 1.2)
                .padding(.horizontal, 20)

            stub
                .frame(height: Self.stubHeight)
        }
        .frame(width: Self.width, height: height)
        .background { stock }
        .clipShape(Self.outline)
        .overlay {
            Self.outline
                .strokeBorder(.white.opacity(0.42), lineWidth: 1)
        }
        // Collapse text, Canvas artwork, gradients, clip, and outline into one
        // composited surface. During a swipe the GPU moves that surface instead
        // of re-compositing the ticket's internal layers for every drag update.
        .drawingGroup(opaque: false, colorMode: .linear)
        .shadow(color: .black.opacity(0.22), radius: 4, y: 3)
        .shadow(color: .black.opacity(0.24), radius: 28, y: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(card.style.label): \(card.title), \(card.primaryLabel) \(card.primaryValue)"
        )
    }

    private var mainBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("SERIES NO. \(serial)")
                Spacer()
                Text("COVE · \(card.style.label.uppercased())")
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(ink.opacity(0.66))

            HomeTicketPixelField(ink: ink)
                .frame(height: 118)
                .padding(.top, 16)

            Spacer(minLength: 12)

            Text(displayTitle.uppercased())
                .font(.system(size: 34, weight: .black, design: .rounded))
                .tracking(-1.4)
                .foregroundStyle(ink)
                .lineLimit(3)
                .minimumScaleFactor(0.68)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle = card.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
               !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.82))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            HStack(alignment: .top, spacing: 20) {
                ticketFact(card.primaryLabel, value: card.primaryValue)
                ticketFact(card.secondaryLabel, value: card.secondaryValue)
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
    }

    private var stub: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                ticketFact("Admit", value: admissionValue)
                Spacer(minLength: 18)
                ticketFact("Reference", value: referenceValue, trailing: true)
            }

            HomeTicketBarcode(seed: card.id, ink: ink)
                .frame(height: 30)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func ticketFact(
        _ label: String,
        value: String,
        trailing: Bool = false
    ) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(ink.opacity(0.58))

            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(ink)
                .lineLimit(2)
                .minimumScaleFactor(0.68)
                .multilineTextAlignment(trailing ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }

    private var stock: some View {
        LinearGradient(
            colors: card.style.homeTicketGradient,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            RadialGradient(
                colors: [.white.opacity(0.14), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 360
            )
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.12)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 96)
        }
    }

    private var ink: Color { card.style.homeTicketInk }

    private var displayTitle: String {
        card.title
            .replacingOccurrences(of: " · ", with: "\n")
            .replacingOccurrences(of: " — ", with: "\n")
    }

    private var serial: String {
        String(
            card.id.uuidString
                .replacingOccurrences(of: "-", with: "")
                .prefix(3)
        )
    }

    private var admissionValue: String {
        if let seat = card.details.first(where: {
            $0.label.localizedCaseInsensitiveContains("seat")
        })?.value {
            return seat
        }
        return switch card.style {
        case .receipt: "PAID"
        case .ticket, .generic: "ONE"
        }
    }

    private var referenceValue: String {
        card.details.first { $0.label.localizedCaseInsensitiveContains("reference") }?.value
            ?? serial
    }
}

private extension WalletCard.Style {
    var homeTicketGradient: [Color] {
        switch self {
        case .receipt:
            [
                Color(red: 0.96, green: 0.34, blue: 0.14),
                Color(red: 0.72, green: 0.13, blue: 0.08)
            ]
        case .ticket:
            [
                Color(red: 0.24, green: 0.36, blue: 0.94),
                Color(red: 0.10, green: 0.20, blue: 0.76)
            ]
        case .generic:
            [
                Color(red: 0.02, green: 0.62, blue: 0.52),
                Color(red: 0.02, green: 0.30, blue: 0.43)
            ]
        }
    }

    var homeTicketInk: Color {
        Color(red: 0.98, green: 0.96, blue: 0.88)
    }
}

/// Registration marks that brighten toward the centre, echoing the reference's
/// halftone field without baking an image into the card.
private struct HomeTicketPixelField: View {
    let ink: Color

    private static let columns = 11
    private static let rows = 7

    var body: some View {
        Canvas { context, size in
            let xStep = size.width / CGFloat(Self.columns)
            let yStep = size.height / CGFloat(Self.rows)

            for row in 0..<Self.rows {
                for column in 0..<Self.columns {
                    let strength = Self.intensity(row: row, column: column)
                    let side = 3.5 + CGFloat(strength) * 3.5
                    let centre = CGPoint(
                        x: (CGFloat(column) + 0.5) * xStep,
                        y: (CGFloat(row) + 0.5) * yStep
                    )
                    let rect = CGRect(
                        x: centre.x - side / 2,
                        y: centre.y - side / 2,
                        width: side,
                        height: side
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 1),
                        with: .color(ink.opacity(0.28 + strength * 0.62))
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }

    private static func intensity(row: Int, column: Int) -> Double {
        let dx = Double(column) - Double(Self.columns - 1) / 2
        let dy = Double(row) - Double(Self.rows - 1) / 2
        let distance = sqrt(dx * dx + dy * dy)
        return max(0, 1 - distance / 6.2)
    }
}

private struct HomeTicketBarcode: View {
    let seed: UUID
    let ink: Color

    private var bars: [CGFloat] {
        seed.uuidString.utf8.map { byte in
            CGFloat(Int(byte) % 3 + 1)
        }
    }

    var body: some View {
        Canvas { context, size in
            guard !bars.isEmpty else { return }

            let gap: CGFloat = 1.8
            let totalGap = gap * CGFloat(bars.count - 1)
            let totalUnits = bars.reduce(CGFloat.zero, +)
            let unit = max((size.width - totalGap) / totalUnits, 0)
            var x: CGFloat = 0

            for width in bars {
                let barWidth = width * unit
                context.fill(
                    Path(CGRect(x: x, y: 0, width: barWidth, height: size.height)),
                    with: .color(ink.opacity(0.94))
                )
                x += barWidth + gap
            }
        }
        .accessibilityHidden(true)
    }
}

private struct HomeTicketTearLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct HomeTicketShape: InsettableShape {
    let cornerRadius: CGFloat
    let notchRadius: CGFloat
    let stubHeight: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let body = Path(
            roundedRect: insetRect,
            cornerRadius: max(cornerRadius - insetAmount, 0)
        )
        let tearY = insetRect.maxY - stubHeight

        var notches = Path()
        notches.addEllipse(
            in: CGRect(
                x: insetRect.minX - notchRadius,
                y: tearY - notchRadius,
                width: notchRadius * 2,
                height: notchRadius * 2
            )
        )
        notches.addEllipse(
            in: CGRect(
                x: insetRect.maxX - notchRadius,
                y: tearY - notchRadius,
                width: notchRadius * 2,
                height: notchRadius * 2
            )
        )
        return body.subtracting(notches)
    }

    func inset(by amount: CGFloat) -> HomeTicketShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

#Preview {
    NavigationStack {
        HomeDashboardView()
    }
    .modelContainer(for: [ShelfItem.self, ChatThread.self], inMemory: true)
    .environment(\.aiServices, .mock)
}
