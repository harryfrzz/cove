import SwiftData
import SwiftUI

/// Landing dashboard: what Cove has captured that still matters at a glance —
/// the wallet passes and what's coming up. Browsing the full shelf is the
/// shelf tab's job, so the page stays a summary rather than a second feed.
struct HomeDashboardView: View {
    /// Wired by the shell so the wallet header can jump to its tab.
    var onOpenWallet: () -> Void = {}

    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]
    @State private var categorizer = ShelfCategorizer.shared

    /// Tapped pass, held alone over the blurred page.
    @State private var expandedCard: WalletCard?
    /// Zoom sources: passes grow out of the fan, event cards out of the
    /// carousel — the same opening the album piles use.
    @Namespace private var passNamespace
    @Namespace private var eventNamespace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !walletCards.isEmpty {
                    walletSection
                }

                if !eventRows.isEmpty {
                    eventsSection
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

    // MARK: - Chrome

    /// Named for the destination, not the app: the dock is icon-only, so every
    /// page's header has to say which tab you are standing on. The orange item
    /// count keeps its trailing slot.
    private var topBar: some View {
        CoveScreenHeader("Home") {
            Text("\(items.count)")
                .font(.system(.subheadline, design: .serif, weight: .bold))
                .foregroundStyle(.orange)
                .frame(minWidth: 36, minHeight: 36)
                .glassEffect(.regular, in: Circle())
                .accessibilityLabel("\(items.count) items")
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

    /// Upcoming reads as a deck of cards rather than a list: each event gets
    /// its own coloured face, and the next one peeks in from the trailing edge
    /// so the row is visibly scrollable without an indicator.
    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(hasUpcoming ? "Upcoming" : "Events & tickets")

            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(eventRows) { row in
                        NavigationLink {
                            ItemDetailView(item: row.item)
                                .navigationTransition(
                                    .zoom(sourceID: row.id, in: eventNamespace)
                                )
                        } label: {
                            EventCard(row: row)
                        }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: row.id, in: eventNamespace)
                        // Poster proportions, roughly 1:1.45 against the fixed
                        // height. Narrower than this and the title runs out of
                        // room — event names arrive with venues and route
                        // codes attached, and they were being scaled down to
                        // fit rather than simply fitting.
                        .containerRelativeFrame(.horizontal) { length, _ in
                            length * 0.50
                        }
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }

    private var hasUpcoming: Bool {
        eventRows.contains { ($0.date ?? .distantPast) >= .now }
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

// MARK: - Event row

private struct EventRow: Identifiable {
    let id: UUID
    let title: String
    let when: String?
    let place: String?
    let date: Date?
    let item: ShelfItem
}

/// One upcoming event as a coloured card: name and countdown at the top, the
/// date as the centrepiece, venue along the bottom.
private struct EventCard: View {
    let row: EventRow

    private static let height: CGFloat = 264
    private static let cornerRadius: CGFloat = 24

    /// Built once per card. Rebuilding it inside `body` would re-run the
    /// seeded draws on every animation frame.
    private let palette: CoveGradientPalette

    init(row: EventRow) {
        self.row = row
        palette = CoveGradientPalette(seed: row.id)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CoveGradientBackdrop(palette: palette)

            numeral
            content
        }
        .frame(height: Self.height)
        .clipShape(.rect(cornerRadius: Self.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(.white.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title), \(countdown). \(footnote)")
    }

    /// The day, set oversized in the bottom-left and deliberately running off
    /// both edges so the card crops it. Sitting between the gradient and the
    /// text, it reads as part of the artwork rather than as a label.
    private var numeral: some View {
        Group {
            if let date = row.date {
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 132, weight: .heavy, design: .serif))
            } else {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 92, weight: .semibold))
            }
        }
        // Ink, not white. The shader lifts every gradient toward white to keep
        // the body text readable, which left a white numeral with nothing to
        // sit against — on the paler rolls it broke up into disconnected
        // shapes. A dark tint is legible against all of them.
        .foregroundStyle(CoveTheme.ink.opacity(0.15))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        // Overhangs enough to crop, not so much that the digits lose the
        // curves that identify them.
        .offset(x: -10, y: 26)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Everything readable, hard-aligned to the leading edge: countdown,
    /// title, then the month and place pinned to the bottom-right where the
    /// numeral leaves room.
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(countdown.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(CoveTheme.ink.opacity(0.5))
                .lineLimit(1)

            Text(displayTitle)
                .font(.system(size: 19, weight: .bold, design: .serif))
                .foregroundStyle(CoveTheme.ink)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 1) {
                if let date = row.date {
                    Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                        .font(.system(size: 13, weight: .black))
                        .tracking(1.8)
                        .foregroundStyle(CoveTheme.ink.opacity(0.72))
                }
                Text(footnote)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CoveTheme.ink.opacity(0.55))
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
    }

    /// Extracted titles carry their own separators — "Flight 6E 331 · BLR →
    /// DEL". Left to wrap on its own the line broke after "331" and started
    /// the next one with the dangling "·". The separator is already a natural
    /// division in the title, so it becomes the line break instead of a
    /// character that can be orphaned onto one.
    private var displayTitle: String {
        row.title
            .replacingOccurrences(of: " · ", with: "\n")
            .replacingOccurrences(of: " — ", with: "\n")
    }

    /// "Today" / "in 12 days", falling back to the printed string when the
    /// date never parsed.
    private var countdown: String {
        guard let date = row.date else {
            return row.when ?? "Saved"
        }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.relative(presentation: .named))
    }

    private var footnote: String {
        let parts = [row.place, row.when]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
        return parts.first ?? "Upcoming"
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
    /// Bumped once the passes are on screen; every card's keyframe timeline
    /// hangs off this, so one change fires the whole wave.
    @State private var waveToken = 0
    /// How far the deck has been swiped through, in cards.
    @State private var cycle = 0
    /// Horizontal travel of the card being thrown, and which card that is —
    /// tracked by id, not by slot, so the throw stays with the departing pass
    /// once the deck reorders underneath it.
    @State private var swipeX: CGFloat = 0
    @State private var swipingID: UUID?

    private static let cardHeight: CGFloat = 212
    private static let peek: CGFloat = 66
    private static let maxCards = 4
    /// Headroom above and below the fan so a lifted card never clips.
    private static let liftRoom: CGFloat = 22
    /// Beat before the wave starts, so the page has settled first.
    private static let introDelay: Duration = .seconds(0.18)
    /// Sideways travel that commits to sending the front pass to the back.
    private static let swipeThreshold: CGFloat = 56
    /// How far the thrown card carries before the deck reorders behind it.
    private static let throwDistance: CGFloat = 380
    private static let throwDuration: TimeInterval = 0.18

    /// The latest few passes — the whole deck the home fan ever deals with.
    private var deck: [WalletCard] { Array(cards.prefix(Self.maxCards)) }

    /// That deck rotated to wherever swiping has left it. Swiping cycles
    /// within these cards rather than pulling further back through the
    /// wallet, so the pass thrown off the front lands in the back slot and
    /// stays there instead of dropping out of the fan.
    private var shown: [WalletCard] {
        guard !deck.isEmpty else { return [] }
        let start = ((cycle % deck.count) + deck.count) % deck.count
        return Array(deck[start...] + deck[..<start])
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Order 0 is the front pass; it draws on top and sits lowest.
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, card in
                // Deliberately not a Button. `.gesture` sits at lower
                // precedence than gestures a subview defines, and a Button
                // handles its touches internally — so the swipe below never
                // got to start. A tap gesture at this level competes fairly
                // with the drag: the tap loses the moment the finger travels.
                WalletCardView(card: card)
                    .contentShape(.rect(cornerRadius: 22))
                .scaleEffect(1 - CGFloat(index) * 0.015)
                .rotationEffect(Self.tilt(order: index), anchor: .center)
                // Zoom reads the frame recorded here, so it has to sit inside
                // the padding below — that padding is what actually places the
                // card in the fan.
                .matchedTransitionSource(id: card.id, in: namespace)
                // Fan spacing as real layout, not `.offset`. An offset moves
                // pixels but leaves the layout frame at the bottom of the
                // stack, which is exactly the frame the zoom transition would
                // return the pass to — the passes above the front one would
                // drop to the wrong place on close.
                .padding(.bottom, CGFloat(index) * Self.peek)
                .offset(x: card.id == swipingID ? swipeX : 0)
                .rotationEffect(
                    .degrees(card.id == swipingID ? Double(swipeX) * 0.018 : 0),
                    anchor: .bottom
                )
                // Intro wave, applied after the fan layout so the resting
                // arrangement is untouched.
                .modifier(
                    FanLiftWave(
                        order: index,
                        restingTilt: Self.tilt(order: index),
                        trigger: waveToken
                    )
                )
                // Swipe only belongs to the pass on top; the rest keep their
                // tap. `.subviews` disables this gesture without disabling
                // the tap attached below it.
                .gesture(cycleDrag(card: card), including: index == 0 ? .all : .subviews)
                .onTapGesture { onSelect(card) }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Open pass") { onSelect(card) }
                .accessibilityAction(named: "Send to back") { cycleFan(direction: -1, card: card) }
                .zIndex(-Double(index))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(
            height: Self.cardHeight + CGFloat(max(shown.count - 1, 0)) * Self.peek + 14,
            alignment: .bottom
        )
        .padding(.horizontal, 6)
        .padding(.top, 4 + Self.liftRoom)
        .padding(.bottom, 8 + Self.liftRoom)
        // Keyed on the card count so the wave also runs once the passes
        // finish loading, not just on the first empty render. The task is
        // torn down with the view, so coming back to Home starts a fresh one.
        .task(id: shown.count) { await startWave() }
    }

    /// Fires the wave once, a beat after the fan is on screen. Reduce Motion
    /// leaves the token alone, so no card timeline ever starts.
    private func startWave() async {
        guard !reduceMotion, !shown.isEmpty else { return }
        guard (try? await Task.sleep(for: Self.introDelay)) != nil else { return }
        waveToken += 1
    }

    // MARK: - Swipe to cycle

    /// Sideways drag on the front pass. `minimumDistance` keeps taps going to
    /// the button underneath, and the gesture is only attached to order 0.
    private func cycleDrag(card: WalletCard) -> some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                swipingID = card.id
                swipeX = value.translation.width
            }
            .onEnded { value in
                // Flick counts as well as distance, so a short fast swipe
                // still sends the pass back.
                let travel = value.translation.width + value.predictedEndTranslation.width * 0.25
                guard abs(travel) > Self.swipeThreshold else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                        swipeX = 0
                    }
                    return
                }
                cycleFan(direction: travel < 0 ? -1 : 1, card: card)
            }
    }

    /// Front pass goes to the back, everything behind it steps forward. Two
    /// beats: the card carries on out the way it was thrown while it is still
    /// in front, then the deck reorders and it slides back in from the side —
    /// by then it is the back card, so it tucks in under the others.
    private func cycleFan(direction: CGFloat, card: WalletCard) {
        guard deck.count > 1 else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { swipeX = 0 }
            return
        }

        withAnimation(.easeIn(duration: Self.throwDuration)) {
            swipeX = direction * Self.throwDistance
        }
        Task {
            try? await Task.sleep(for: .seconds(Self.throwDuration))
            withAnimation(.spring(response: 0.46, dampingFraction: 0.84)) {
                cycle += 1
                swipeX = 0
            }
            try? await Task.sleep(for: .seconds(0.5))
            if swipingID == card.id { swipingID = nil }
        }
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

// MARK: - Fan intro wave

/// The four things a card does on its way through the wave. Tracked as one
/// value so the keyframe timelines stay in step with each other.
private struct FanLift {
    var rise: CGFloat = 0
    var scale: CGFloat = 1
    /// 0 resting in the fan, 1 fully square to the page.
    var straighten: Double = 0
    /// 0 flat on the stack, 1 fully off it.
    var shadow: Double = 0
}

/// One card's trip through the wave: it lifts off the fan, straightens as it
/// comes up, casts a deeper shadow at the top, then springs back down. Each
/// card runs its own copy of this timeline offset by `order`, and the offset
/// is much shorter than the trip, so several cards are always mid-flight —
/// that overlap is what makes it a wave instead of a queue.
private struct FanLiftWave: ViewModifier {
    let order: Int
    /// The card's resting fan angle, so the lift can rotate against it.
    let restingTilt: Angle
    let trigger: Int

    /// Gap between one card starting its rise and the next starting its own.
    private static let stagger: TimeInterval = 0.075
    private static let riseDuration: TimeInterval = 0.3
    private static let settleDuration: TimeInterval = 0.42

    /// Nonzero even for the front card — a keyframe needs real duration.
    private var delay: TimeInterval { 0.01 + Double(order) * Self.stagger }
    /// Deeper cards travel further; the parallax reads as depth.
    private var height: CGFloat { 13 + CGFloat(order) * 2 }

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: FanLift(), trigger: trigger) { view, lift in
            view
                .rotationEffect(.degrees(-restingTilt.degrees * lift.straighten), anchor: .center)
                .scaleEffect(lift.scale)
                .offset(y: lift.rise)
                .shadow(
                    color: .black.opacity(0.3 * lift.shadow),
                    radius: 20 * lift.shadow,
                    y: 14 * lift.shadow
                )
        } keyframes: { _ in
            // Bouncy on the way up and down: the overshoot at the top is what
            // makes the card read as light card stock rather than a slab.
            KeyframeTrack(\.rise) {
                LinearKeyframe(0, duration: delay)
                SpringKeyframe(-height, duration: Self.riseDuration, spring: .bouncy(extraBounce: 0.3))
                SpringKeyframe(0, duration: Self.settleDuration, spring: .bouncy(extraBounce: 0.2))
            }
            KeyframeTrack(\.scale) {
                LinearKeyframe(1, duration: delay)
                SpringKeyframe(1.035, duration: Self.riseDuration, spring: .bouncy(extraBounce: 0.25))
                SpringKeyframe(1, duration: Self.settleDuration, spring: .snappy)
            }
            // Straighten and shadow ride the motion rather than lead it, so
            // they stay smooth while the height springs past its target.
            KeyframeTrack(\.straighten) {
                LinearKeyframe(0, duration: delay)
                CubicKeyframe(0.55, duration: Self.riseDuration)
                CubicKeyframe(0, duration: Self.settleDuration)
            }
            KeyframeTrack(\.shadow) {
                LinearKeyframe(0, duration: delay)
                CubicKeyframe(1, duration: Self.riseDuration)
                CubicKeyframe(0, duration: Self.settleDuration)
            }
        }
    }
}

#Preview {
    NavigationStack {
        HomeDashboardView()
    }
    .modelContainer(for: ShelfItem.self, inMemory: true)
    .environment(\.aiServices, .mock)
}
