import SwiftData
import SwiftUI

// MARK: - Card model

/// Display model for one wallet pass, derived from a shelf item's structured
/// extraction — or, for an item the user pinned by hand, the neutral pass face.
struct WalletCard: Identifiable {
    enum Style {
        case receipt
        case ticket
        case generic

        /// The ticket stock itself: pale, so the print on top can be ink
        /// rather than white-on-saturated.
        var gradient: [Color] {
            switch self {
            case .receipt: [Color(red: 0.89, green: 0.93, blue: 0.60), Color(red: 0.72, green: 0.90, blue: 0.66)]
            case .ticket: [Color(red: 0.76, green: 0.84, blue: 1.00), Color(red: 0.78, green: 0.71, blue: 0.97)]
            case .generic: [Color(red: 0.69, green: 0.93, blue: 0.82), Color(red: 0.59, green: 0.89, blue: 0.79)]
            }
        }

        /// What's printed on that stock — a deep tint of the card's own hue,
        /// so each pass reads as one colour family rather than black on pastel.
        var ink: Color {
            switch self {
            case .receipt: Color(red: 0.19, green: 0.28, blue: 0.08)
            case .ticket: Color(red: 0.18, green: 0.16, blue: 0.44)
            case .generic: Color(red: 0.05, green: 0.29, blue: 0.24)
            }
        }

        var label: String {
            switch self {
            case .receipt: "Receipt"
            case .ticket: "Ticket"
            case .generic: "Pass"
            }
        }

        var systemImage: String {
            switch self {
            case .receipt: "receipt"
            case .ticket: "ticket"
            case .generic: "wallet.pass"
            }
        }

        /// Readable on the cream panel, where the pastel stock isn't behind it.
        var accent: Color {
            switch self {
            case .receipt: Color(red: 0.36, green: 0.50, blue: 0.10)
            case .ticket: Color(red: 0.40, green: 0.33, blue: 0.84)
            case .generic: Color(red: 0.06, green: 0.47, blue: 0.39)
            }
        }
    }

    /// One labelled fact for the detail panel under the carousel. Kept as a
    /// list rather than fixed slots because a flight has more worth showing
    /// (seat, gate, reference) than a receipt does.
    struct Detail: Identifiable {
        var id: String { label }
        let label: String
        let value: String
        let systemImage: String
    }

    let id: UUID
    let style: Style
    let title: String
    let subtitle: String?
    let primaryLabel: String
    let primaryValue: String
    let secondaryLabel: String
    let secondaryValue: String
    let details: [Detail]
    let item: ShelfItem

    @MainActor
    static func card(for item: ShelfItem) -> WalletCard {
        let savedDate = item.createdAt.formatted(date: .abbreviated, time: .omitted)

        if let extraction = item.extraction, extraction.category == "receipt" {
            return WalletCard(
                id: item.id,
                style: .receipt,
                title: extraction.merchant ?? item.title,
                subtitle: extraction.expenseCategory,
                primaryLabel: "Total",
                primaryValue: "\(extraction.currency ?? "")\(extraction.total ?? "—")",
                secondaryLabel: "Date",
                secondaryValue: extraction.date ?? savedDate,
                details: compact([
                    ("Amount", "\(extraction.currency ?? "")\(extraction.total ?? "")", "indianrupeesign.circle"),
                    ("Date", extraction.date, "calendar"),
                    ("Category", extraction.expenseCategory, "tag")
                ]),
                item: item
            )
        }

        if let extraction = item.extraction, extraction.category == "event" {
            return WalletCard(
                id: item.id,
                style: .ticket,
                title: extraction.eventTitle ?? item.title,
                subtitle: extraction.eventLocation,
                primaryLabel: "Starts",
                primaryValue: extraction.eventStart ?? "—",
                secondaryLabel: "Where",
                secondaryValue: extraction.eventLocation ?? "—",
                details: compact([
                    ("Location", extraction.eventLocation, "mappin.and.ellipse"),
                    ("Time", extraction.eventStart, "clock"),
                    ("Ends", extraction.eventEnd, "clock.badge.checkmark")
                ]),
                item: item
            )
        }

        // Travel and cinema tickets. Without this branch they fell through to
        // the generic case below and lost seat, gate, and reference entirely.
        if let extraction = item.extraction, extraction.category == "ticket" {
            return WalletCard(
                id: item.id,
                style: .ticket,
                title: extraction.ticketTitle ?? item.title,
                subtitle: extraction.venueOrOperator,
                primaryLabel: "Departs",
                primaryValue: extraction.ticketDateTime ?? "—",
                secondaryLabel: "Seat",
                secondaryValue: extraction.seatDetails ?? "—",
                details: compact([
                    ("Seat", extraction.seatDetails, "chair"),
                    ("Time", extraction.ticketDateTime, "clock"),
                    ("Operator", extraction.venueOrOperator, "building.2"),
                    ("Reference", extraction.referenceNumber, "number"),
                    ("Fare", extraction.price, "creditcard")
                ]),
                item: item
            )
        }

        // Everything past here is an item the user pinned by hand that carries
        // no extraction. It gets the neutral "Pass" face — deriving the style
        // from `ShelfCategorizer` instead would dress a plain photo up as a
        // Ticket on the strength of a loose CLIP match, which is the same
        // guesswork that put those photos in the wallet to begin with.
        return WalletCard(
            id: item.id,
            style: .generic,
            title: item.title,
            subtitle: item.summary,
            primaryLabel: "Saved",
            primaryValue: savedDate,
            secondaryLabel: "Kind",
            secondaryValue: item.kind.label,
            details: compact([
                ("Saved", savedDate, "tray.and.arrow.down"),
                ("Kind", item.kind.label, "square.stack")
            ]),
            item: item
        )
    }

    /// Drops facts the extraction didn't find, so the panel never shows a
    /// labelled blank.
    private static func compact(_ raw: [(String, String?, String)]) -> [Detail] {
        raw.compactMap { label, value, symbol in
            guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return Detail(label: label, value: value, systemImage: symbol)
        }
    }
}

// MARK: - Membership

extension ShelfItem {
    /// Extraction categories that describe an actual pass.
    private static let passCategories: Set<String> = ["receipt", "event", "ticket"]

    /// Whether this item belongs in the wallet.
    ///
    /// Membership has to be *earned* by a structured extraction, never inferred
    /// from image similarity. `ShelfCategorizer.bucket(for:)` is a zero-shot
    /// CLIP match against prompts like "a ticket for a concert or event", with
    /// a deliberately low floor so the shelf's category grid stays populated —
    /// which means an ordinary camera-roll photo can clear it and land in
    /// `.events`. Reading that as wallet membership put plain photos in the
    /// wallet dressed as tickets, with no seat, time, or total to show.
    ///
    /// So: a real extraction, or an explicit pin. Nothing else.
    var isWalletPass: Bool {
        guard processingState == .ready else { return false }
        if isInWallet { return true }
        // Both halves are required. The category says what the classifier
        // *called* it; `describesAPass` says whether the extracted fields bear
        // that out. A camera-roll photo forced into "event" clears the first
        // and fails the second.
        guard let extraction, Self.passCategories.contains(extraction.category) else {
            return false
        }
        return extraction.describesAPass
    }
}

// MARK: - Wallet page

struct WalletView: View {
    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which pass the carousel has settled on.
    @State private var selectedID: UUID?
    /// What the panel is currently showing. Trails `selectedID` by one
    /// animation so the slide direction can be decided before it moves.
    @State private var visibleID: UUID?
    @State private var slideForward = true

    private var cards: [WalletCard] {
        items
            .filter(\.isWalletPass)
            .map { WalletCard.card(for: $0) }
    }

    private var visibleCard: WalletCard? {
        cards.first { $0.id == visibleID } ?? cards.first
    }

    private func index(of id: UUID?) -> Int {
        cards.firstIndex { $0.id == id } ?? 0
    }

    var body: some View {
        ZStack {
            CoveInkBackground()

            if cards.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    Spacer(minLength: 8)

                    CoverFlowCarousel(cards: cards, selectedID: $selectedID)

                    pageDots
                        .padding(.top, 4)

                    Text("\(cards.count) pass\(cards.count == 1 ? "" : "es") · built from your screenshots")
                        .font(.footnote)
                        .foregroundStyle(CoveTheme.inkSecondary)
                        .padding(.top, 14)

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 20)
                // Reserved rather than overlaid: the pass is the thing being
                // looked at, and a sheet that covers it to describe it is
                // working against itself.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let card = visibleCard {
                        WalletDetailPanel(card: card)
                            // Rebuilding on id change is what gives the panel
                            // something to transition *between*.
                            .id(card.id)
                            .transition(panelTransition)
                    }
                }
            }
        }
        // Cove's own header rather than the system navigation bar: Wallet was
        // the one root screen wearing a different kind of title, which read as
        // a pushed page instead of a tab.
        .safeAreaInset(edge: .top) {
            CoveScreenHeader("Wallet") {
                if !cards.isEmpty {
                    Text("\(cards.count)")
                        .font(.system(.subheadline, design: .serif, weight: .bold))
                        .foregroundStyle(.orange)
                        .frame(minWidth: 36, minHeight: 36)
                        .glassEffect(.regular, in: Circle())
                        .accessibilityLabel("\(cards.count) passes")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if selectedID == nil { selectedID = cards.first?.id }
            if visibleID == nil { visibleID = selectedID }
        }
        // Direction is resolved first, then the swap is animated — otherwise
        // the transition would read a stale edge and slide the wrong way.
        .onChange(of: selectedID) { previous, current in
            guard let current, current != visibleID else { return }
            slideForward = index(of: current) >= index(of: previous)
            // Damped harder than the carousel's own settle: the panel carries
            // text, and overshoot on a paragraph reads as a wobble rather than
            // as weight.
            withAnimation(
                reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.88)
            ) {
                visibleID = current
            }
        }
    }

    /// Thumbnail, title, and facts travel as one block, and the block turns.
    ///
    /// The panel swings in on the same vertical axis the covers above it rotate
    /// around, hinged on the edge the finger came from — so the sheet reads as
    /// the back face of the pass being turned to, not as a second list sliding
    /// past. It also sits down a few points and rises as it squares up, which
    /// is what keeps a pure rotation from looking like it is on rails.
    private var panelTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: PanelPhase(
                    dx: slideForward ? 54 : -54,
                    dy: 10,
                    angle: slideForward ? -26 : 26,
                    anchor: slideForward ? .leading : .trailing,
                    blur: 7,
                    scale: 0.95,
                    opacity: 0
                ),
                identity: PanelPhase.settled
            ),
            removal: .modifier(
                active: PanelPhase(
                    dx: slideForward ? -44 : 44,
                    dy: 6,
                    angle: slideForward ? 20 : -20,
                    anchor: slideForward ? .trailing : .leading,
                    blur: 9,
                    scale: 0.93,
                    opacity: 0
                ),
                identity: PanelPhase.settled
            )
        )
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(cards) { card in
                Capsule()
                    .fill(CoveTheme.ink.opacity(card.id == visibleID ? 0.55 : 0.16))
                    .frame(width: card.id == visibleID ? 18 : 6, height: 6)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.32), value: visibleID)
        .accessibilityHidden(true)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wallet.pass")
                .font(.system(size: 44, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CoveTheme.ink)
            Text("No passes yet")
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(CoveTheme.ink)
            Text("Receipts and tickets you capture appear here automatically.\nAny other item can be added from its detail page.")
                .font(.subheadline)
                .foregroundStyle(CoveTheme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 34)
        .padding(.horizontal, 28)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .padding(32)
    }
}

// MARK: - Cover Flow carousel

/// Cover Flow: the active pass faces straight forward at full size while its
/// neighbours tilt away around the vertical axis and sit back in depth.
///
/// Hand-driven rather than a paging `ScrollView` — the transform for every
/// card is a pure function of its distance from centre, so it tracks the
/// finger continuously instead of interpolating between fixed pages, and the
/// release settles on a spring rather than the system's scroll deceleration.
private struct CoverFlowCarousel: View {
    let cards: [WalletCard]
    @Binding var selectedID: UUID?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Which pass is centred, and how far the finger has pulled away from it.
    @State private var index = 0
    @State private var drag: CGFloat = 0

    static let cardHeight: CGFloat = 206

    /// Turn angle of a card one full step off centre.
    private static let maxAngle: Double = 42
    /// Neighbours land at 82% — small enough to sit behind, large enough to
    /// still read as a card rather than a chip.
    private static let sideScale: CGFloat = 0.18
    /// Fraction of an over-drag past the first or last pass that actually
    /// moves. The deck is not a loop, and a hard stop at the ends reads as a
    /// dropped gesture — this gives the edge somewhere to go and a reason to
    /// come back.
    private static let edgeResistance: CGFloat = 0.32

    /// How many cards either side of centre get built. Spacing compresses past
    /// the first neighbour, so nothing beyond about ±2.5 is still on screen —
    /// 4 leaves a margin for a fast flick without building the whole wallet.
    ///
    /// This matters more than it looks: every card carries a `rotation3DEffect`,
    /// a blur, a shadow pair and a `ShelfThumbnail` that decodes a bitmap, so
    /// an unwindowed `ForEach` did all of that once per pass on every frame of
    /// a drag.
    private static let windowRadius = 4

    /// Finger travel that turns one card all the way over.
    ///
    /// Deliberately *not* the visual spacing. Driving the transform straight
    /// off `step` meant ~144pt of movement spun a card through its full 42°,
    /// which read as twitchy — a thumb twitch visibly threw the deck. Cards
    /// still sit the same distance apart; they just take more finger to move.
    private static let dragPerCard: CGFloat = 230

    /// How much of the system's velocity projection is allowed to count toward
    /// where the deck lands. The raw prediction models a scroll throw and
    /// overshoots badly here: a brisk 60pt swipe can project past 400pt, which
    /// was enough to skip a card.
    private static let flickWeight: CGFloat = 0.22

    /// Momentum beyond which a swipe reads as a deliberate flick and is allowed
    /// to skip a second card. Below it, one swipe moves exactly one card no
    /// matter how far the projection runs.
    private static let flickThreshold: CGFloat = 620

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let cardWidth = min(width * 0.88, 376)
            let step = cardWidth * 0.46
            let progress = CGFloat(index) - drag / Self.dragPerCard

            ZStack {
                ForEach(window(around: progress), id: \.card.id) { entry in
                    cover(
                        entry.card,
                        distance: CGFloat(entry.position) - progress,
                        isFocused: entry.position == index,
                        cardWidth: cardWidth,
                        step: step
                    )
                }
            }
            .frame(width: width, height: Self.cardHeight)
            .contentShape(.rect)
            // High priority so a moving touch is resolved as a drag before
            // any card's NavigationLink can claim it as a tap. A stationary
            // touch fails the 8pt minimum and falls through to the link, so
            // tap-to-open still works.
            .highPriorityGesture(swipe)
        }
        .frame(height: Self.cardHeight)
        .padding(.vertical, 18)
        .onAppear(perform: syncFromSelection)
        .onChange(of: index) { _, new in
            guard cards.indices.contains(new) else { return }
            selectedID = cards[new].id
        }
        // A pass leaving the wallet can strand the deck past its own end.
        .onChange(of: cards.count) { _, count in
            index = min(index, max(count - 1, 0))
            drag = 0
        }
    }

    /// One card close enough to centre to be worth building.
    private struct Windowed {
        let position: Int
        let card: WalletCard
    }

    /// The slice of the deck to draw for a given scroll position.
    ///
    /// Clamped rather than wrapped, and tolerant of a `progress` dragged past
    /// either end: an overscroll can put the centre outside the array, in which
    /// case the range collapses and nothing is drawn rather than trapping on a
    /// bad subscript.
    private func window(around progress: CGFloat) -> [Windowed] {
        guard !cards.isEmpty else { return [] }

        let centre = Int(progress.rounded())
        let lower = max(0, centre - Self.windowRadius)
        let upper = min(cards.count - 1, centre + Self.windowRadius)
        guard lower <= upper else { return [] }

        return (lower...upper).map { Windowed(position: $0, card: cards[$0]) }
    }

    private func cover(
        _ card: WalletCard,
        distance: CGFloat,
        isFocused: Bool,
        cardWidth: CGFloat,
        step: CGFloat
    ) -> some View {
        let clamped = max(-3, min(3, distance))
        let magnitude = abs(clamped)
        let side: CGFloat = clamped < 0 ? -1 : 1
        let x = side * (min(magnitude, 1) * step + max(magnitude - 1, 0) * step * 0.42)
        let angle = Double(max(-1, min(1, clamped))) * Self.maxAngle

        return NavigationLink {
            ItemDetailView(item: card.item)
        } label: {
            WalletCardView(card: card, height: Self.cardHeight)
                .frame(width: cardWidth)
        }
        .buttonStyle(.plain)
        .rotation3DEffect(
            .degrees(angle),
            axis: (x: 0, y: 1, z: 0),
            anchor: .center,
            perspective: 0.62
        )
        .scaleEffect(max(0.80, 1 - magnitude * Self.sideScale))
        .offset(x: x)
        .blur(radius: min(magnitude, 1.5) * 1.6)
        .opacity(max(0.4, 1 - magnitude * 0.22))
        .zIndex(10 - Double(magnitude))
        // Keyed to the *settled* index, not the live distance. Deriving it
        // from `magnitude` meant cards became tappable part-way through a drag
        // — and which one crossed the threshold under the finger depended on
        // which way you swiped, so a backward swipe could hand the touch to a
        // card that had just switched on and open it on release.
        //
        // `index` cannot change until the gesture ends, so the set of tappable
        // views is now fixed for the whole drag.
        .allowsHitTesting(isFocused)
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                drag = resisted(value.translation.width)
            }
            .onEnded { value in
                let travel = value.translation.width
                // Split the system's projection into what the finger actually
                // covered and what it merely predicts from velocity. The two
                // deserve very different weight — the first is intent, the
                // second is a guess tuned for scroll views.
                let momentum = value.predictedEndTranslation.width - travel
                let effective = travel + momentum * Self.flickWeight

                // However far the finger actually went is honoured in full —
                // clamping that would rubber-band a deliberate long drag back
                // to one card after the deck had visibly moved two. Momentum
                // may add one card on top of it, and only on a real flick.
                let travelled = max(1, (abs(travel) / Self.dragPerCard).rounded())
                let limit = travelled + (abs(momentum) > Self.flickThreshold ? 1 : 0)

                let steps = Int(
                    max(-limit, min(limit, (-effective / Self.dragPerCard).rounded()))
                )

                let target = min(max(index + steps, 0), max(cards.count - 1, 0))
                withAnimation(
                    reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.82)
                ) {
                    index = target
                    drag = 0
                }
            }
    }

    /// Drag, with everything past the ends of the deck damped instead of
    /// followed. Distances are in points; the range is what is left in front of
    /// and behind the pass currently centred.
    private func resisted(_ raw: CGFloat) -> CGFloat {
        let ahead = CGFloat(max(cards.count - 1 - index, 0)) * Self.dragPerCard
        let behind = CGFloat(index) * Self.dragPerCard

        if raw < -ahead {
            return -ahead - (-raw - ahead) * Self.edgeResistance
        }
        if raw > behind {
            return behind + (raw - behind) * Self.edgeResistance
        }
        return raw
    }

    private func syncFromSelection() {
        if let selectedID, let found = cards.firstIndex(where: { $0.id == selectedID }) {
            index = found
        } else if let first = cards.first {
            selectedID = first.id
            index = 0
        }
    }
}

private struct PanelPhase: ViewModifier {
    let dx: CGFloat
    var dy: CGFloat = 0
    var angle: Double = 0
    var anchor: UnitPoint = .center
    let blur: CGFloat
    let scale: CGFloat
    let opacity: Double

    static let settled = PanelPhase(dx: 0, blur: 0, scale: 1, opacity: 1)

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0, y: 1, z: 0),
                anchor: anchor,
                // Shallower than the carousel's 0.62. The panel is a wide, flat
                // block, and at the covers' perspective its far edge stretched
                // far enough to tear.
                perspective: 0.42
            )
            .blur(radius: blur)
            .opacity(opacity)
            .offset(x: dx, y: dy)
    }
}

// MARK: - Detail panel

private struct WalletDetailPanel: View {
    let card: WalletCard

    /// The one-line summary the pipeline wrote for this capture. Falls back to
    /// the start of the extracted text so the paragraph is never empty on an
    /// item the language model never got to.
    private var blurb: String? {
        if let summary = card.item.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            return summary
        }
        guard let text = card.item.extractedText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " "),
              !text.isEmpty else { return nil }
        return String(text.prefix(160))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if card.item.imageData != nil {
                    ShelfThumbnail(item: card.item)
                        .frame(width: 62, height: 62)
                        .clipShape(.rect(cornerRadius: 13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13)
                                .strokeBorder(CoveTheme.hairline, lineWidth: 1)
                        }
                        .accessibilityLabel("Original screenshot")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.system(.title3, design: .serif, weight: .bold))
                        .foregroundStyle(CoveTheme.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle = card.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(CoveTheme.inkSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }

            if card.details.isEmpty {
                Text("Nothing else was readable in this capture.")
                    .font(.caption)
                    .foregroundStyle(CoveTheme.inkSecondary)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10, alignment: .topLeading),
                        GridItem(.flexible(), spacing: 10, alignment: .topLeading)
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(card.details.prefix(4)) { detail in
                        fact(detail)
                    }
                }
            }

            if let blurb {
                Text(blurb)
                    .font(.footnote)
                    .foregroundStyle(CoveTheme.inkSecondary)
                    .lineSpacing(2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            openButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        // The floating dock is drawn over the foot of this sheet, so the call
        // to action has to clear it rather than sit underneath it.
        .padding(.bottom, CoveTabBar.occupiedHeight + 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 132, alignment: .top)
        // Glass, not the flat white this was: the sheet runs edge to edge under
        // the deck now, and an opaque slab that wide cut the page in half.
        // Blurring what passes behind it is also what tells you the pass is
        // still up there.
        .glassEffect(.regular, in: Self.sheetShape)
        .overlay {
            Self.sheetShape
                .stroke(CoveTheme.hairline, lineWidth: 1)
                .mask(alignment: .top) {
                    // Only the top edge. The stroke is there to catch the light
                    // where the sheet meets the page; carried around the sides
                    // it draws a box around something with no bottom.
                    LinearGradient(
                        colors: [.white, .white.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                }
        }
        .shadow(color: .black.opacity(0.10), radius: 18, y: -6)
        .ignoresSafeArea(edges: .bottom)
    }

    /// Rounded at the top, square at the bottom: this is a surface the page
    /// slides under, not a card floating on it.
    private static let sheetShape = UnevenRoundedRectangle(
        topLeadingRadius: 30,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 0,
        topTrailingRadius: 30
    )

    /// Full-width call to action closing the panel, the way a product card
    /// ends in its one obvious next step.
    private var openButton: some View {
        NavigationLink {
            ItemDetailView(item: card.item)
        } label: {
            HStack(spacing: 6) {
                Text("More details")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(CoveTheme.background)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(CoveTheme.ink, in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
        .accessibilityLabel("More details about \(card.title)")
        .accessibilityHint("Opens the original screenshot and everything Cove read from it")
    }

    private func fact(_ detail: WalletCard.Detail) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: detail.systemImage)
                .font(.caption2)
                .foregroundStyle(card.style.accent)
                .frame(width: 13)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 0) {
                Text(detail.label.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(CoveTheme.inkSecondary)
                Text(detail.value)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CoveTheme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(detail.label): \(detail.value)")
    }
}

// MARK: - Lift

private struct PassShadow: ViewModifier {
    var lift: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.20 * min(lift, 1.4)), radius: 3 * lift, y: 2 * lift)
            .shadow(color: .black.opacity(0.22 * min(lift, 1.4)), radius: 22 * lift, y: 16 * lift)
    }
}

private extension View {
    func passShadow(lift: CGFloat = 1) -> some View {
        modifier(PassShadow(lift: lift))
    }
}

// MARK: - Pass card

struct WalletCardView: View {
    let card: WalletCard
    var height: CGFloat = 158
    var cornerRadius: CGFloat = 20
    var showsShadow: Bool = true

    private static let stubWidth: CGFloat = 116

    private var outline: TicketShape {
        TicketShape(cornerRadius: cornerRadius, notchRadius: 8, stubInset: Self.stubWidth)
    }

    var body: some View {
        HStack(spacing: 0) {
            printedHalf
            tearLine
            stub
        }
        .frame(height: height)
        .background { stock }
        .clipShape(outline)
        .overlay {
            outline.stroke(.white.opacity(0.55), lineWidth: 1)
        }
        .passShadow(lift: showsShadow ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.style.label): \(card.title), \(card.primaryLabel) \(card.primaryValue)")
    }

    private var printedHalf: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(card.style.label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(card.style.ink.opacity(0.62))
                .lineLimit(1)
                .frame(height: 28, alignment: .center)

            Spacer(minLength: 6)

            Text(card.title)
                .font(.system(.subheadline, design: .serif, weight: .bold))
                .foregroundStyle(card.style.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(card.primaryValue)
                .font(.caption)
                .foregroundStyle(card.style.ink.opacity(0.78))
                .lineLimit(1)
                .padding(.top, 3)

            if let subtitle = card.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(card.style.ink.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tearLine: some View {
        TearLine()
            .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
            .foregroundStyle(card.style.ink.opacity(0.3))
            .frame(width: 1.2)
            .padding(.vertical, 14)
    }

    private var stub: some View {
        VStack(spacing: 6) {
            if card.item.imageData != nil {
                ShelfThumbnail(item: card.item)
                    .frame(height: 40)
                    // Screenshots are the most saturated thing on a pastel
                    // ticket, and at this size they carry almost no readable
                    // information — so they get pulled toward the card's own
                    // colour rather than sitting on it like a sticker.
                    .saturation(0.55)
                    .overlay(card.style.gradient[0].opacity(0.22))
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(0.65), lineWidth: 1)
                    }
            }

            ForEach(stubFacts) { fact in
                VStack(alignment: .leading, spacing: 0) {
                    Text(fact.label.uppercased())
                        .font(.system(size: 7.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(card.style.ink.opacity(0.55))
                    Text(fact.value)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(card.style.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 12)
        .frame(width: Self.stubWidth)
    }

    private var stubFacts: [WalletCard.Detail] {
        Array(card.details.prefix(card.item.imageData == nil ? 3 : 2))
    }

    private var stock: some View {
        LinearGradient(
            colors: card.style.gradient,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: card.style.systemImage)
                .font(.system(size: 104, weight: .light))
                .foregroundStyle(.white.opacity(0.18))
                .rotationEffect(.degrees(-12))
                .offset(x: 74, y: 4)
        }
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [.white.opacity(0.42), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 26)
        }
        .allowsHitTesting(false)
    }

    private struct TearLine: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            return path
        }
    }
}

private struct TicketShape: Shape {
    var cornerRadius: CGFloat = 20
    var notchRadius: CGFloat = 8
    var stubInset: CGFloat

    func path(in rect: CGRect) -> Path {
        let tearX = rect.maxX - stubInset
        let body = Path(roundedRect: rect, cornerRadius: cornerRadius)

        var notches = Path()
        notches.addEllipse(
            in: CGRect(
                x: tearX - notchRadius,
                y: rect.minY - notchRadius,
                width: notchRadius * 2,
                height: notchRadius * 2
            )
        )
        notches.addEllipse(
            in: CGRect(
                x: tearX - notchRadius,
                y: rect.maxY - notchRadius,
                width: notchRadius * 2,
                height: notchRadius * 2
            )
        )
        return body.subtracting(notches)
    }
}

// MARK: - Single pass

struct WalletPassDetailView: View {
    let card: WalletCard

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    /// Drives the staged open: shadow, then backdrop, then the card itself.
    @State private var expanded = false
    /// Detail content waits for the card to finish before arriving.
    @State private var detailsIn = false

    /// Past this much downward travel the drag counts as a dismiss.
    private static let dismissThreshold: CGFloat = 130

    /// How far through a dismiss drag we are, 0…1.
    private var dragProgress: CGFloat {
        min(max(dragOffset, 0) / Self.dismissThreshold, 1)
    }

    private func stage(_ delay: Double) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.46, dampingFraction: 0.78).delay(delay)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(expanded ? 1 : 0)
                .animation(stage(0.06), value: expanded)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture { dismiss() }

            GeometryReader { proxy in
                ScrollView {
                    passSheet(minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .task {
            expanded = true
            guard !reduceMotion else {
                detailsIn = true
                return
            }
            try? await Task.sleep(for: .milliseconds(360))
            detailsIn = true
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CoveTheme.ink.opacity(0.75))
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
            .padding(.top, 8)
            .accessibilityLabel("Close pass")
        }
    }

    /// The scrolling body of the pass: card on top, source shot and caption
    /// staged in underneath. Held in its own function rather than inline in the
    /// `ScrollView` — as one expression the whole thing is more than the type
    /// checker can resolve, and it fails the `ScrollView` initializer as
    /// ambiguous rather than pointing at anything here.
    private func passSheet(minHeight: CGFloat) -> some View {
        VStack(spacing: 20) {
            WalletCardView(
                card: card,
                height: 196,
                cornerRadius: expanded ? 14 : 24,
                showsShadow: false
            )
            .scaleEffect(expanded ? 1 : 0.92)
            .animation(stage(0.10), value: expanded)
            .passShadow(lift: expanded ? 1.3 : 0.45)
            .animation(stage(0), value: expanded)
            .gesture(dismissDrag)

            Group {
                if card.item.imageData != nil {
                    sourceShot
                }

                caption
            }
            .opacity(detailsIn ? 1 : 0)
            .offset(y: detailsIn ? 0 : 16)
            .blur(radius: detailsIn ? 0 : 4)
            .animation(stage(0), value: detailsIn)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(minHeight: minHeight, alignment: .center)
        .offset(y: max(dragOffset, 0))
        .scaleEffect(1 - dragProgress * 0.06)
        .blur(radius: dragProgress * 4)
        .opacity(1 - dragProgress * 0.35)
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dragOffset = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > Self.dismissThreshold {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private var sourceShot: some View {
        ShelfThumbnail(item: card.item)
            .frame(height: 260)
            .clipShape(.rect(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.white.opacity(0.5), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 10, y: 5)
            .accessibilityLabel("Original screenshot")
    }

    private var caption: some View {
        VStack(spacing: 4) {
            Text(card.item.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CoveTheme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("Saved \(card.item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(CoveTheme.inkSecondary)
        }
    }
}
