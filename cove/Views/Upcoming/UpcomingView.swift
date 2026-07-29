import SwiftData
import SwiftUI
import UIKit

/// A dedicated chronological view for events and dated tickets. Each entry is
/// presented as an observation specimen: a playful technical record rather
/// than another Wallet ticket.
struct UpcomingView: View {
    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]
    @Namespace private var detailNamespace
    /// Set by tapping a card in the deck; the list rows below still push
    /// through their own `NavigationLink`.
    @State private var openedEntryID: UUID?

    private static let dateDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue
    )

    /// How many of the soonest events are dealt into the pile. Matches Wallet's
    /// deck depth; everything further out stays a list, where a date you are
    /// scanning for is quicker to find than behind a run of swipes.
    private static let deckCount = 3
    /// `UpcomingEventCard` is otherwise free to grow with its title; the deck
    /// needs one fixed height or the peek between cards drifts per card.
    private static let cardHeight: CGFloat = 236

    private var entries: [UpcomingEntry] {
        let startOfToday = Calendar.current.startOfDay(for: .now)

        return items
            .compactMap { item -> UpcomingEntry? in
                guard item.processingState == .ready, let extraction = item.extraction else {
                    return nil
                }

                let title: String?
                let printedDate: String?
                let location: String?
                let kind: String

                switch extraction.category {
                case "event":
                    title = extraction.eventTitle
                    printedDate = extraction.eventStart
                    location = extraction.eventLocation
                    kind = "Event"
                case "ticket":
                    title = extraction.ticketTitle
                    printedDate = extraction.ticketDateTime
                    location = extraction.venueOrOperator
                    kind = extraction.ticketType?.capitalized ?? "Ticket"
                default:
                    return nil
                }

                guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }

                let date = parsedDate(from: printedDate)
                if let date, date < startOfToday {
                    return nil
                }

                return UpcomingEntry(
                    id: item.id,
                    title: title,
                    printedDate: printedDate,
                    date: date,
                    location: location,
                    kind: kind,
                    item: item
                )
            }
            .sorted {
                ($0.date ?? .distantFuture, $0.item.createdAt)
                    < ($1.date ?? .distantFuture, $1.item.createdAt)
            }
    }

    var body: some View {
        ZStack {
            CoveInkBackground()

            if entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        deck

                        laterHeading

                        if laterEntries.isEmpty {
                            laterEmptyNote
                        }

                        ForEach(laterEntries) { entry in
                            NavigationLink {
                                ItemDetailView(item: entry.item)
                                    .navigationTransition(
                                        .zoom(sourceID: entry.id, in: detailNamespace)
                                    )
                            } label: {
                                UpcomingEventCard(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    CoveHaptics.impact(.soft)
                                }
                            )
                            .matchedTransitionSource(id: entry.id, in: detailNamespace)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectHidden(true, for: .bottom)
            }
        }
        // The deck cannot use a `NavigationLink` — a Button swallows the touches
        // its swipe needs — so the soonest events push from here instead.
        .navigationDestination(item: $openedEntryID) { id in
            if let entry = entries.first(where: { $0.id == id }) {
                ItemDetailView(item: entry.item)
                    .navigationTransition(.zoom(sourceID: id, in: detailNamespace))
            }
        }
        .safeAreaBar(edge: .top) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// The soonest events, stacked. Square rather than fanned: Wallet's lean
    /// suits printed ticket stock, these are posters and a tilt reads as a
    /// mistake on them.
    private var deck: some View {
        CoveCardDeck(
            cards: deckEntries,
            cardHeight: Self.cardHeight,
            peek: 34,
            maxCards: Self.deckCount,
            openActionName: "Open event",
            namespace: detailNamespace,
            onSelect: { openedEntryID = $0.id }
        ) { entry, _ in
            UpcomingEventCard(entry: entry)
        }
    }

    private var laterHeading: some View {
        Text("Later")
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.8)
            .textCase(.uppercase)
            .foregroundStyle(CoveTheme.ink.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }

    /// The heading stays even with nothing under it, so a short list reads as
    /// "that is everything" rather than as a section that failed to load.
    private var laterEmptyNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(CoveTheme.ink.opacity(0.5))

            Text(
                entries.count == 1
                    ? "Just the one event for now."
                    : "Nothing further out — everything coming up is in the stack above."
            )
            .font(.footnote)
            .foregroundStyle(CoveTheme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private var deckEntries: [UpcomingEntry] {
        Array(entries.prefix(Self.deckCount))
    }

    private var laterEntries: [UpcomingEntry] {
        Array(entries.dropFirst(Self.deckCount))
    }

    private var topBar: some View {
        CoveScreenHeader("Upcoming") {
            Text("\(entries.count)")
                .font(.system(.subheadline, design: .serif, weight: .bold))
                .foregroundStyle(.orange)
                .frame(minWidth: 36, minHeight: 36)
                .glassEffect(.regular, in: Circle())
                .accessibilityLabel("\(entries.count) upcoming")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 38, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(CoveTheme.ink.opacity(0.62))

            Text("Nothing coming up")
                .font(.system(.title2, design: .serif, weight: .semibold))
                .foregroundStyle(CoveTheme.ink)

            Text("Dated events and tickets will appear here once Cove reads them.")
                .font(.subheadline)
                .foregroundStyle(CoveTheme.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 28)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .padding(.horizontal, 36)
    }

    private func parsedDate(from value: String?) -> Date? {
        guard let value, let detector = Self.dateDetector else { return nil }
        let range = NSRange(value.startIndex..., in: value)
        return detector.firstMatch(in: value, range: range)?.date
    }
}

private struct UpcomingEntry: Identifiable {
    let id: UUID
    let title: String
    let printedDate: String?
    let date: Date?
    let location: String?
    let kind: String
    let item: ShelfItem
}

/// A compact event poster using the same blue and warm ink as Wallet tickets.
private struct UpcomingEventCard: View {
    let entry: UpcomingEntry

    @Environment(\.colorScheme) private var colorScheme

    private static let blueTop = Color(red: 0.24, green: 0.36, blue: 0.94)
    private static let blueBottom = Color(red: 0.10, green: 0.20, blue: 0.76)
    private static let warmInk = Color(red: 0.98, green: 0.96, blue: 0.88)
    private var secondaryText: Color { Self.warmInk.opacity(0.68) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titlePanel
                .padding(.horizontal, 20)
                .padding(.top, 20)

            Spacer(minLength: 18)

            bottomInfo
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, minHeight: 228, alignment: .leading)
        .background {
            LinearGradient(
                colors: [Self.blueTop, Self.blueBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .overlay(alignment: .topLeading) {
            RadialGradient(
                colors: [Color.white.opacity(0.12), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 220
            )
            .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.34 : 0.16),
            radius: colorScheme == .dark ? 18 : 14,
            y: 8
        )
        .contentShape(.rect(cornerRadius: 28))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var titlePanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 12) {
                Text(entry.title)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .tracking(-0.8)
                    .foregroundStyle(Self.warmInk)
                    .lineLimit(3)
                    .minimumScaleFactor(0.68)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Text(relativeDate.uppercased())
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(0.55)
                    .foregroundStyle(Self.warmInk)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(Self.warmInk.opacity(0.13), in: Capsule())
            }

            if let location = clean(entry.location) {
                Label(location, systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomInfo: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Color.clear
                .frame(width: 112, height: 88)

            VStack(alignment: .leading, spacing: 2) {
                Text(month)
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .tracking(1.2)
                Text(year)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .opacity(0.64)
            }
            .foregroundStyle(Self.warmInk)
            .padding(.bottom, 7)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text("STARTS")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(secondaryText)

                Text(timeLabel)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Self.warmInk)
                    .lineLimit(1)
            }
            .padding(.bottom, 7)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Self.blueBottom)
                .frame(width: 32, height: 32)
                .background(Self.warmInk, in: Circle())
                .padding(.bottom, 2)
        }
        .overlay(alignment: .bottomLeading) {
            OutlinedDay(text: day, color: UIColor(Self.warmInk))
                .frame(width: 160, height: 112, alignment: .bottomLeading)
                // Oversized and deliberately pushed beyond both edges so the
                // rounded card crops it like display type on a poster.
                .offset(x: -40, y: 46)
                .accessibilityHidden(true)
        }
    }

    private var day: String {
        entry.date?.formatted(.dateTime.day(.twoDigits)) ?? "–"
    }

    private var month: String {
        entry.date?.formatted(.dateTime.month(.abbreviated)).uppercased() ?? "TBD"
    }

    private var year: String {
        entry.date?.formatted(.dateTime.year()) ?? "TBD"
    }

    private var relativeDate: String {
        guard let date = entry.date else { return "Date pending" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.relative(presentation: .named))
    }

    private var timeLabel: String {
        if let date = entry.date {
            return date.formatted(.dateTime.hour().minute())
        }
        return clean(entry.printedDate) ?? "TBD"
    }

    private var accessibilityText: String {
        [entry.kind, entry.title, entry.printedDate, entry.location]
            .compactMap { clean($0) }
            .joined(separator: ", ")
    }

    private func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

/// UIKit's stroke-only glyph rendering gives the date the outlined poster
/// treatment without adding a background tile behind it.
private struct OutlinedDay: UIViewRepresentable {
    let text: String
    let color: UIColor

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.backgroundColor = .clear
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.68
        label.baselineAdjustment = .alignBaselines
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        let baseFont = UIFont.systemFont(ofSize: 116, weight: .black)
        let descriptor = baseFont.fontDescriptor.withDesign(.rounded) ?? baseFont.fontDescriptor
        let font = UIFont(descriptor: descriptor, size: 116)

        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .strokeColor: color,
                .strokeWidth: 2.25,
                .foregroundColor: UIColor.clear,
                .kern: -3
            ]
        )
    }
}

#Preview {
    NavigationStack {
        UpcomingView()
    }
    .modelContainer(for: [ShelfItem.self, ChatThread.self], inMemory: true)
}
