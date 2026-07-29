import SwiftData
import SwiftUI

/// A dedicated chronological view for events and dated tickets. It deliberately
/// avoids another collection of cards: dates, a fine timeline, and the event
/// copy itself are the interface.
struct UpcomingView: View {
    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]
    @Namespace private var detailNamespace

    private static let dateDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue
    )

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
                        sectionLabel

                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            NavigationLink {
                                ItemDetailView(item: entry.item)
                                    .navigationTransition(
                                        .zoom(sourceID: entry.id, in: detailNamespace)
                                    )
                            } label: {
                                UpcomingEventCard(
                                    entry: entry,
                                    colorIndex: index
                                )
                            }
                            .buttonStyle(.plain)
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
        .safeAreaBar(edge: .top) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
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

    private var sectionLabel: some View {
        HStack(spacing: 8) {
            Text("ON THE HORIZON")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(CoveTheme.inkSecondary)

            Rectangle()
                .fill(CoveTheme.ink.opacity(0.12))
                .frame(height: 1)
        }
        .padding(.bottom, 2)
        .accessibilityHidden(true)
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

/// One standalone event card. A narrow colour seam and a dedicated date column
/// distinguish each item without returning to the dense ticket treatment used
/// by Wallet.
private struct UpcomingEventCard: View {
    let entry: UpcomingEntry
    let colorIndex: Int

    private static let accents: [Color] = [
        Color(red: 0.18, green: 0.31, blue: 0.88),
        Color(red: 0.92, green: 0.27, blue: 0.10),
        Color(red: 0.02, green: 0.48, blue: 0.39),
        Color(red: 0.43, green: 0.23, blue: 0.76),
        Color(red: 0.76, green: 0.13, blue: 0.35)
    ]

    private var accent: Color {
        Self.accents[colorIndex % Self.accents.count]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            dateStamp

            Rectangle()
                .fill(CoveTheme.ink.opacity(0.10))
                .frame(width: 1)

            details
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 166, alignment: .leading)
        .background(accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 28))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(accent)
                .frame(width: 4)
                .padding(.vertical, 24)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .strokeBorder(accent.opacity(0.14), lineWidth: 1)
        }
        .contentShape(.rect(cornerRadius: 28))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var dateStamp: some View {
        VStack(spacing: 0) {
            Text(day)
                .font(.system(size: 44, weight: .semibold, design: .serif).monospacedDigit())
                .foregroundStyle(CoveTheme.ink)

            Text(month)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(accent)

            if let date = entry.date {
                Text(date.formatted(.dateTime.year()))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(CoveTheme.inkSecondary.opacity(0.72))
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)

            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
                .overlay {
                    Circle()
                        .stroke(accent.opacity(0.18), lineWidth: 6)
                }
                .padding(.bottom, 6)
        }
        .frame(width: 54)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(entry.kind.uppercased())
                Text("·")
                Text(relativeDate.uppercased())
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(accent)

            Text(entry.title)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(CoveTheme.ink)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Spacer(minLength: 8)

            if let timeLabel {
                metadata(systemImage: "clock", text: timeLabel)
            }
            if let location = clean(entry.location) {
                metadata(systemImage: "mappin", text: location)
                    .padding(.top, 5)
            }
        }
    }

    private func metadata(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(CoveTheme.inkSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var day: String {
        entry.date?.formatted(.dateTime.day()) ?? "–"
    }

    private var month: String {
        entry.date?.formatted(.dateTime.month(.abbreviated)).uppercased() ?? "TBD"
    }

    private var relativeDate: String {
        guard let date = entry.date else { return "Date pending" }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.relative(presentation: .named))
    }

    private var timeLabel: String? {
        if let date = entry.date {
            return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return clean(entry.printedDate)
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

#Preview {
    NavigationStack {
        UpcomingView()
    }
    .modelContainer(for: ShelfItem.self, inMemory: true)
}
