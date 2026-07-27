import SwiftData
import SwiftUI

// MARK: - Card model

/// Display model for one wallet pass, derived from a shelf item's structured
/// extraction when available, else from its classification bucket.
struct WalletCard: Identifiable {
    enum Style {
        case receipt
        case ticket
        case generic

        var gradient: [Color] {
            switch self {
            case .receipt: [Color(red: 0.93, green: 0.48, blue: 0.14), Color(red: 0.72, green: 0.26, blue: 0.05)]
            case .ticket: [Color(red: 0.56, green: 0.27, blue: 0.86), Color(red: 0.87, green: 0.27, blue: 0.57)]
            case .generic: [Color(red: 0.22, green: 0.26, blue: 0.34), Color(red: 0.10, green: 0.12, blue: 0.18)]
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
    }

    let id: UUID
    let style: Style
    let title: String
    let subtitle: String?
    let primaryLabel: String
    let primaryValue: String
    let secondaryLabel: String
    let secondaryValue: String
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
                item: item
            )
        }

        let bucket = ShelfCategorizer.shared.bucket(for: item)
        let style: Style = switch bucket {
        case .receipts: .receipt
        case .events: .ticket
        default: .generic
        }
        return WalletCard(
            id: item.id,
            style: style,
            title: item.title,
            subtitle: item.summary,
            primaryLabel: "Saved",
            primaryValue: savedDate,
            secondaryLabel: "Kind",
            secondaryValue: item.kind.label,
            item: item
        )
    }
}

// MARK: - Wallet page

struct WalletView: View {
    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]
    @State private var categorizer = ShelfCategorizer.shared

    private var cards: [WalletCard] {
        items
            .filter { item in
                guard item.processingState == .ready else { return false }
                if item.isInWallet { return true }
                let bucket = categorizer.bucket(for: item)
                return bucket == .receipts || bucket == .events
            }
            .map { WalletCard.card(for: $0) }
    }

    var body: some View {
        ZStack {
            CoveInkBackground()

            if cards.isEmpty {
                emptyState
            } else {
                VStack(spacing: 26) {
                    Spacer(minLength: 0)

                    WalletCarousel(cards: cards)

                    Text("\(cards.count) pass\(cards.count == 1 ? "" : "es") · built from your screenshots")
                        .font(.footnote)
                        .foregroundStyle(CoveTheme.inkSecondary)

                    Spacer(minLength: 0)
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

// MARK: - 3D stacked carousel

/// Horizontal carousel where neighboring passes tilt away and slide behind
/// the focused one — a wallet stack receding into depth.
private struct WalletCarousel: View {
    let cards: [WalletCard]

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: -34) {
                ForEach(cards) { card in
                    NavigationLink {
                        ItemDetailView(item: card.item)
                    } label: {
                        WalletCardView(card: card)
                    }
                    .buttonStyle(.plain)
                    .containerRelativeFrame(.horizontal) { length, _ in
                        length * 0.80
                    }
                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                        content
                            .rotation3DEffect(
                                .degrees(phase.value * -32),
                                axis: (x: 0, y: 1, z: 0),
                                perspective: 0.55
                            )
                            .scaleEffect(1 - abs(phase.value) * 0.16)
                            .offset(x: phase.value * -18, y: abs(phase.value) * 12)
                            .opacity(1 - abs(phase.value) * 0.28)
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, 30)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 38, for: .scrollContent)
        .scrollClipDisabled()
    }
}

// MARK: - Pass card

struct WalletCardView: View {
    let card: WalletCard
    /// Passes render at deck size by default; the popped-out single-pass
    /// view asks for a taller card.
    var height: CGFloat = 212

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Label(card.style.label, systemImage: card.style.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                if card.item.imageData != nil {
                    ShelfThumbnail(item: card.item)
                        .frame(width: 40, height: 40)
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                        }
                }
            }

            Spacer(minLength: 10)

            Text(card.title)
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if let subtitle = card.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .padding(.top, 2)
            }

            perforation
                .padding(.vertical, 14)

            HStack(alignment: .firstTextBaseline) {
                field(label: card.primaryLabel, value: card.primaryValue)
                Spacer()
                field(label: card.secondaryLabel, value: card.secondaryValue, alignment: .trailing)
            }
        }
        .padding(20)
        .frame(height: height)
        .background {
            LinearGradient(
                colors: card.style.gradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .overlay(alignment: .topTrailing) {
            // Soft sheen so the pass reads as a physical card.
            LinearGradient(
                colors: [.white.opacity(0.16), .clear],
                startPoint: .topLeading,
                endPoint: UnitPoint(x: 0.5, y: 0.6)
            )
            .allowsHitTesting(false)
        }
        .clipShape(.rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 16, y: 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.style.label): \(card.title), \(card.primaryLabel) \(card.primaryValue)")
    }

    private var perforation: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(CoveTheme.background)
                .frame(width: 16, height: 16)
                .offset(x: -28)

            Line()
                .stroke(style: StrokeStyle(lineWidth: 1.4, dash: [5, 5]))
                .foregroundStyle(.white.opacity(0.4))
                .frame(height: 1.4)

            Circle()
                .fill(CoveTheme.background)
                .frame(width: 16, height: 16)
                .offset(x: 28)
        }
        .frame(height: 16)
        .padding(.horizontal, -28)
    }

    private func field(label: String, value: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.6))
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

// MARK: - Single pass

/// One pass pulled out of the deck and held alone over a blurred shelf: the
/// card at full size, the screenshot it came from underneath. Dismisses on a
/// downward drag, a tap outside the card, or the close button.
struct WalletPassDetailView: View {
    let card: WalletCard

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // The blur is the whole background: the home page stays visible
            // behind it, softened, so the pass reads as lifted off the page.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture { dismiss() }

            // minHeight centers a short pass on the page and still lets a
            // tall screenshot scroll.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        WalletCardView(card: card, height: 248)

                        if card.item.imageData != nil {
                            sourceShot
                        }

                        caption
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                    // No drag-to-dismiss offset here on purpose. The zoom
                    // transition runs its own interactive dismiss and returns
                    // the pass to the frame it was presented from; shifting
                    // the content ourselves and then calling dismiss() left
                    // that return starting from a displaced frame, which is
                    // what made the pass land off the fan.
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
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

    /// The capture the pass was extracted from — the pass's "original".
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
