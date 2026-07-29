import Foundation

/// Money read back out of receipt extractions.
///
/// Everything here is a reconstruction, not a record. The pipeline stores what
/// the language model read off a screenshot — `total` is a string it was asked
/// to keep to digits, `date` is whatever was printed on the receipt — so this
/// parses rather than sums, and is deliberately conservative about what it
/// counts. A receipt it cannot read a number or a date out of is left out
/// entirely rather than guessed at.
struct SpendingLedger {
    /// The currency the headline is in. Cove has no network, so there are no
    /// exchange rates and no honest way to add two currencies together — the
    /// heaviest one wins the headline and the rest are counted separately.
    let currency: String
    let thisMonth: Decimal
    /// Receipts behind the headline figure.
    let receiptCount: Int
    /// The largest month on record in this currency, which is what the
    /// waterline is measured against.
    let peakMonth: Decimal
    /// Receipts in some other currency, excluded from the total above.
    let excludedCount: Int
    let monthLabel: String

    // MARK: - Building

    static func build(
        from items: [ShelfItem],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> SpendingLedger? {
        struct Entry {
            let amount: Decimal
            let currency: String
            let date: Date
        }

        let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        )

        let entries: [Entry] = items.compactMap { item in
            guard item.processingState == .ready,
                  let extraction = item.extraction,
                  extraction.category == "receipt",
                  let raw = extraction.total,
                  let amount = Self.amount(from: raw),
                  amount > 0
            else { return nil }

            // The printed date if it parses, else when the item was captured.
            // Imported screenshots carry the photo's own date, so the fallback
            // is usually close to when the receipt was actually issued.
            var date = item.createdAt
            if let printed = extraction.date, let detector {
                let range = NSRange(printed.startIndex..., in: printed)
                if let match = detector.firstMatch(in: printed, range: range)?.date {
                    date = match
                }
            }

            return Entry(
                amount: amount,
                currency: (extraction.currency?.trimmingCharacters(in: .whitespaces))
                    .flatMap { $0.isEmpty ? nil : $0 } ?? "",
                date: date
            )
        }

        guard !entries.isEmpty else { return nil }

        // Heaviest currency by receipt count, then by total — a single big
        // purchase abroad should not rename the whole page.
        let byCurrency = Dictionary(grouping: entries, by: \.currency)
        guard let dominant = byCurrency.max(by: { left, right in
            if left.value.count != right.value.count {
                return left.value.count < right.value.count
            }
            return left.value.reduce(0) { $0 + $1.amount }
                < right.value.reduce(0) { $0 + $1.amount }
        }) else { return nil }

        let counted = dominant.value

        // Totals per calendar month, so the waterline has something to measure
        // this month against.
        let byMonth = Dictionary(grouping: counted) { entry in
            calendar.dateComponents([.year, .month], from: entry.date)
        }
        let monthTotals = byMonth.mapValues { group in
            group.reduce(Decimal(0)) { $0 + $1.amount }
        }

        let currentMonth = calendar.dateComponents([.year, .month], from: now)

        return SpendingLedger(
            currency: dominant.key,
            thisMonth: monthTotals[currentMonth] ?? 0,
            receiptCount: byMonth[currentMonth]?.count ?? 0,
            peakMonth: monthTotals.values.max() ?? 0,
            excludedCount: entries.count - counted.count,
            monthLabel: now.formatted(.dateTime.month(.wide)).uppercased()
        )
    }

    /// Digits out of whatever was printed.
    ///
    /// Commas are treated as grouping separators, never as decimal marks: the
    /// extraction schema asks for "digits only, e.g. 22.50", so a comma in the
    /// output is a thousands separator from the receipt itself — and reading
    /// "12,480" as twelve-point-four-eight would be an order-of-magnitude
    /// error, which is the one mistake worth ruling out by construction.
    static func amount(from raw: String) -> Decimal? {
        let kept = raw.filter { $0.isNumber || $0 == "." || $0 == "," }
        guard !kept.isEmpty else { return nil }
        let normalized = kept.replacingOccurrences(of: ",", with: "")
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: - Display

    /// How full the vessel sits: this month against the heaviest month there
    /// has been. A first month is its own peak, so it reads full.
    var level: Double {
        guard peakMonth > 0 else { return 0 }
        return min(Self.double(thisMonth) / Self.double(peakMonth), 1)
    }

    /// The figure itself, currency mark included. Compact only once the number
    /// would otherwise crowd the glass — under ten thousand the exact amount
    /// fits, and an exact amount is what makes the panel worth reading.
    var headline: String {
        let value = Self.double(thisMonth)
        if value >= 10_000 {
            return currency + value.formatted(
                .number.notation(.compactName).precision(.fractionLength(0...1))
            )
        }
        let hasPaise = thisMonth != thisMonth.rounded()
        return currency + value.formatted(
            .number.precision(.fractionLength(hasPaise ? 2 : 0))
        )
    }

    var caption: String {
        guard receiptCount > 0 else {
            return "No receipts captured this month"
        }
        var parts = ["\(receiptCount) receipt\(receiptCount == 1 ? "" : "s")"]
        if thisMonth >= peakMonth {
            parts.append("your heaviest month yet")
        } else if peakMonth > 0 {
            let share = Int((level * 100).rounded())
            parts.append("\(share)% of your biggest month")
        }
        if excludedCount > 0 {
            parts.append("\(excludedCount) in another currency not counted")
        }
        return parts.joined(separator: " · ")
    }

    private static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

private extension Decimal {
    func rounded() -> Decimal {
        var input = self
        var result = Decimal()
        NSDecimalRound(&result, &input, 0, .plain)
        return result
    }
}
