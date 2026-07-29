import SwiftUI

/// A pile of cards: the front one at full size with the tops of the ones behind
/// it showing, and a sideways throw that sends the front card to the back.
///
/// Extracted from Wallet's home fan so Upcoming could stack its events the same
/// way. The two differ only in trim — Wallet leans its rear cards into a loose
/// hand-stacked fan, Upcoming stacks square — so the resting tilt and sideways
/// separation are injected and default to none.
///
/// The throw is deliberately three beats rather than one animation: throw the
/// front card clear, promote the cards waiting behind it, then bring the thrown
/// card back from off-screen once it owns the rear z-position. Collapsing that
/// into a single move makes the departing card cut through the pile.
struct CoveCardDeck<Card: Identifiable, Content: View>: View where Card.ID: Hashable {
    let cards: [Card]
    /// Cards are pinned to this height. A deck of differently sized cards has
    /// no consistent peek to work with.
    let cardHeight: CGFloat
    /// How much of each card behind the front one stays visible.
    var peek: CGFloat = 42
    /// Depth of the pile; anything past this is not dealt.
    var maxCards: Int = 3
    /// Headroom above and below so a lifted card never clips.
    var liftRoom: CGFloat = 22
    /// Resting lean per position, front card first. Zero by default.
    var restingTilt: (Int) -> Angle = { _ in .zero }
    /// Resting sideways separation per position — only worth having when the
    /// cards are also tilted, otherwise it reads as misalignment.
    var restingOffset: (Int) -> CGFloat = { _ in 0 }
    var openActionName: String = "Open card"
    var sendToBackActionName: String = "Send to back"
    let namespace: Namespace.ID
    let onSelect: (Card) -> Void
    @ViewBuilder let content: (Card, Int) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the deck has been swiped through, in cards.
    @State private var cycle = 0
    /// Horizontal travel of the card being thrown, and which card that is —
    /// tracked by id, not by slot, so the throw stays with the departing card
    /// once the deck reorders underneath it.
    @State private var swipeX: CGFloat = 0
    @State private var swipingID: Card.ID?
    /// Locks the deck while its three-stage throw/reorder/return is underway.
    @State private var isCycling = false
    /// Cards rise into the pile once, back to front. Tracking ids instead of a
    /// single flag also gives a newly inserted card its own entrance without
    /// replaying the animation for cards that are already on screen.
    @State private var revealedCardIDs: Set<Card.ID> = []

    /// Sideways travel that commits to sending the front card to the back.
    private static var swipeThreshold: CGFloat { 56 }
    /// How far the thrown card carries before the deck reorders behind it.
    private static var throwDistance: CGFloat { 380 }
    private static var throwDuration: TimeInterval { 0.2 }
    /// The newly exposed front cards settle before the old front card returns
    /// from off-screen into the rear slot.
    private static var reorderDuration: TimeInterval { 0.22 }
    private static var returnDuration: TimeInterval { 0.48 }
    /// How far below its slot a card waits before its entrance.
    private static var entranceDrop: CGFloat { 46 }

    /// The cards this deck ever deals with.
    private var deck: [Card] { Array(cards.prefix(maxCards)) }

    /// That deck rotated to wherever swiping has left it. Swiping cycles within
    /// these cards rather than pulling further back through the collection, so
    /// the card thrown off the front lands in the back slot and stays there.
    private var shown: [Card] {
        guard !deck.isEmpty else { return [] }
        let start = ((cycle % deck.count) + deck.count) % deck.count
        return Array(deck[start...] + deck[..<start])
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Order 0 is the front card; it draws on top and sits lowest.
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, card in
                cardView(card, index: index)
            }
        }
        .allowsHitTesting(!isCycling)
        .frame(maxWidth: .infinity)
        .frame(
            height: cardHeight + CGFloat(max(shown.count - 1, 0)) * peek + 14,
            alignment: .bottom
        )
        .padding(.horizontal, 6)
        .padding(.top, 4 + liftRoom)
        .padding(.bottom, 8 + liftRoom)
        .task(id: deck.map(\.id)) {
            await revealNewCards()
        }
    }

    /// Placement values are resolved up front rather than inline: the same
    /// chain written as one expression is more than the type checker will sit
    /// through once `Card` and `Content` are generic.
    private func cardView(_ card: Card, index: Int) -> some View {
        let isRevealed = reduceMotion || revealedCardIDs.contains(card.id)
        let isSwiping = card.id == swipingID
        let scale = (1 - CGFloat(index) * 0.015) * (isRevealed ? 1 : 0.92)
        let dx: CGFloat = restingOffset(index) + (isSwiping ? swipeX : 0)
        let dy: CGFloat = isRevealed ? 0 : Self.entranceDrop
        let swipeTilt = Angle.degrees(isSwiping ? Double(swipeX) * 0.018 : 0)

        // Deliberately not a Button. `.gesture` sits at lower precedence than
        // gestures a subview defines, and a Button handles its touches
        // internally — so the swipe below never got to start. A tap gesture at
        // this level competes fairly with the drag: the tap loses the moment
        // the finger travels.
        return content(card, index)
            .frame(height: cardHeight)
            .contentShape(.rect(cornerRadius: 24))
            .scaleEffect(scale, anchor: .bottom)
            .rotationEffect(restingTilt(index), anchor: .center)
            // Zoom reads the frame recorded here, so it has to sit inside the
            // padding below — that padding is what actually places the card in
            // the pile.
            .matchedTransitionSource(id: card.id, in: namespace)
            // Peek spacing as real layout, not `.offset`. An offset moves
            // pixels but leaves the layout frame at the bottom of the stack,
            // which is exactly the frame the zoom transition would return the
            // card to — the cards above the front one would drop to the wrong
            // place on close.
            .padding(.bottom, CGFloat(index) * peek)
            .offset(x: dx, y: dy)
            .opacity(isRevealed ? 1 : 0)
            .rotationEffect(swipeTilt, anchor: .bottom)
            // Swipe only belongs to the card on top; the rest keep their tap.
            // `.subviews` disables this gesture without disabling the tap
            // attached below it.
            .gesture(cycleDrag(card: card), including: index == 0 ? .all : .subviews)
            .onTapGesture {
                CoveHaptics.impact(.soft)
                onSelect(card)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: LocalizedStringKey(openActionName)) { onSelect(card) }
            .accessibilityAction(named: LocalizedStringKey(sendToBackActionName)) {
                cycleDeck(direction: -1, card: card)
            }
            .zIndex(-Double(index))
    }

    // MARK: - Entrance

    /// Builds the pile from the rear card toward the front so every card gets a
    /// readable upward pop instead of the top card immediately covering the
    /// entrances below it.
    @MainActor
    private func revealNewCards() async {
        let pendingIDs = deck.reversed().map(\.id).filter {
            !revealedCardIDs.contains($0)
        }
        guard !pendingIDs.isEmpty else { return }

        if reduceMotion {
            revealedCardIDs.formUnion(pendingIDs)
            return
        }

        // Give SwiftUI one frame to lay out the cards in their lowered state.
        await Task.yield()

        for (index, id) in pendingIDs.enumerated() {
            guard !Task.isCancelled else { return }

            if index > 0 {
                try? await Task.sleep(for: .milliseconds(85))
                guard !Task.isCancelled else { return }
            }

            withAnimation(.spring(response: 0.46, dampingFraction: 0.7)) {
                _ = revealedCardIDs.insert(id)
            }
        }
    }

    // MARK: - Swipe to cycle

    /// Sideways drag on the front card. `minimumDistance` keeps taps going to
    /// the tap gesture above, and this is only attached at order 0.
    private func cycleDrag(card: Card) -> some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                swipingID = card.id
                swipeX = value.translation.width
            }
            .onEnded { value in
                // Flick counts as well as distance, so a short fast swipe
                // still sends the card back.
                let travel = value.translation.width + value.predictedEndTranslation.width * 0.25
                guard abs(travel) > Self.swipeThreshold else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                        swipeX = 0
                    }
                    return
                }
                cycleDeck(direction: travel < 0 ? -1 : 1, card: card)
            }
    }

    /// Front card goes to the back, everything behind it steps forward. Three
    /// beats: throw the card clear, promote the waiting cards, then return the
    /// thrown card from the side after it owns the rear z-position.
    private func cycleDeck(direction: CGFloat, card: Card) {
        guard deck.count > 1 else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { swipeX = 0 }
            return
        }
        guard !isCycling else { return }

        isCycling = true
        swipingID = card.id

        if reduceMotion {
            cycle += 1
            swipeX = 0
            swipingID = nil
            isCycling = false
            return
        }

        withAnimation(.easeIn(duration: Self.throwDuration)) {
            swipeX = direction * Self.throwDistance
        }

        Task { @MainActor in
            // First let the front card clear the pile completely.
            try? await Task.sleep(for: .seconds(Self.throwDuration))

            // Keep that card parked off-screen while the remaining cards step
            // forward. Its id now belongs to the rear, so its return will be
            // painted underneath the promoted cards.
            withAnimation(.snappy(duration: Self.reorderDuration, extraBounce: 0.04)) {
                cycle += 1
            }
            try? await Task.sleep(for: .seconds(Self.reorderDuration * 0.72))

            // Only now bring the old front card back, into its new rear slot.
            withAnimation(.spring(response: Self.returnDuration, dampingFraction: 0.8)) {
                swipeX = 0
            }

            try? await Task.sleep(for: .seconds(Self.returnDuration))
            if swipingID == card.id { swipingID = nil }
            isCycling = false
        }
    }
}
