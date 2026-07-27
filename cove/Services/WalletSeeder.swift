#if DEBUG
import SwiftData
import UIKit

/// Demo-only seeder (`--seed-wallet` launch argument): inserts a handful of
/// ready-made receipt/ticket passes so the wallet carousel has depth to show.
@MainActor
enum WalletSeeder {
    private static let seedTag = "seed-pass"

    struct Seed {
        let title: String
        let extraction: ItemExtraction
        let color: UIColor
        let lines: [String]
    }

    static func seedIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--seed-wallet") else { return }

        let context = ModelContext(CoveStore.shared)
        let already = ((try? context.fetch(FetchDescriptor<ShelfItem>())) ?? [])
            .contains { $0.tags.contains(seedTag) }
        guard !already else { return }

        for seed in seeds {
            let item = ShelfItem(
                kind: .screenshot,
                title: seed.title,
                imageData: renderImage(color: seed.color, lines: seed.lines),
                summary: nil,
                tags: [seedTag],
                processingState: .ready
            )
            item.extraction = seed.extraction
            // What OCR would have pulled off the rendered pass. Without it the
            // demo passes have nothing for the wallet panel's blurb to show.
            item.extractedText = seed.lines
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            item.isInWallet = true
            context.insert(item)
        }
        try? context.save()
    }

    private static let seeds: [Seed] = [
        Seed(
            title: "Blue Bottle Coffee",
            extraction: ItemExtraction(
                category: "receipt", merchant: "Blue Bottle Coffee",
                total: "14.20", currency: "$", date: "21 Jul 2026", expenseCategory: "dining"
            ),
            color: UIColor(red: 0.36, green: 0.24, blue: 0.12, alpha: 1),
            lines: ["BLUE BOTTLE COFFEE", "", "Cold brew        $6.50", "Croissant        $5.20", "Tip              $2.50", "", "TOTAL           $14.20"]
        ),
        Seed(
            title: "Whole Foods Market",
            extraction: ItemExtraction(
                category: "receipt", merchant: "Whole Foods Market",
                total: "86.35", currency: "$", date: "19 Jul 2026", expenseCategory: "groceries"
            ),
            color: UIColor(red: 0.08, green: 0.35, blue: 0.22, alpha: 1),
            lines: ["WHOLE FOODS", "", "Produce         $32.10", "Bakery          $11.25", "Pantry          $43.00", "", "TOTAL           $86.35"]
        ),
        Seed(
            title: "Arctic Monkeys Live",
            extraction: ItemExtraction(
                category: "event", eventTitle: "Arctic Monkeys Live",
                eventStart: "Sat 8 Aug · 8:00 PM", eventLocation: "Kia Forum, LA"
            ),
            color: UIColor(red: 0.16, green: 0.12, blue: 0.38, alpha: 1),
            lines: ["ARCTIC MONKEYS", "LIVE 2026", "", "SAT 8 AUG · 8 PM", "KIA FORUM", "", "SEC 104 ROW F"]
        ),
        Seed(
            title: "Dune: Part Three",
            extraction: ItemExtraction(
                category: "ticket",
                ticketType: "movie", ticketTitle: "Dune: Part Three",
                venueOrOperator: "IMAX Screen 1", ticketDateTime: "Sun 30 Aug · 7:15 PM",
                seatDetails: "Screen 1 · Seat J12", referenceNumber: "BMS-88214471", price: "450"
            ),
            color: UIColor(red: 0.55, green: 0.33, blue: 0.08, alpha: 1),
            lines: ["DUNE: PART THREE", "IMAX", "", "SUN 30 AUG · 7:15 PM", "SCREEN 1 · SEAT J12"]
        ),
        Seed(
            title: "Chennai Central → Bengaluru",
            extraction: ItemExtraction(
                category: "ticket",
                ticketType: "train", ticketTitle: "Chennai Central to Bengaluru",
                venueOrOperator: "Shatabdi Express 12007", ticketDateTime: "Mon 3 Aug · 6:00 AM",
                seatDetails: "Coach C4 · Seat 27", referenceNumber: "PNR 4821093567", price: "845"
            ),
            color: UIColor(red: 0.10, green: 0.30, blue: 0.30, alpha: 1),
            lines: ["SHATABDI EXPRESS 12007", "", "CHENNAI CTL → BLR", "MON 3 AUG · 6:00 AM", "COACH C4 · SEAT 27"]
        ),
        Seed(
            title: "Coldplay World Tour",
            extraction: ItemExtraction(
                category: "ticket",
                ticketType: "event", ticketTitle: "Coldplay World Tour",
                venueOrOperator: "DY Patil Stadium", ticketDateTime: "Fri 21 Aug · 7:00 PM",
                seatDetails: "Gate 3 · GA Lower", referenceNumber: "TKT-CP2026-0091", price: "6500"
            ),
            color: UIColor(red: 0.42, green: 0.05, blue: 0.20, alpha: 1),
            lines: ["COLDPLAY", "WORLD TOUR 2026", "", "FRI 21 AUG · 7:00 PM", "DY PATIL STADIUM", "", "GATE 3 · GA LOWER"]
        ),
        Seed(
            title: "IKEA",
            extraction: ItemExtraction(
                category: "receipt", merchant: "IKEA",
                total: "12,480", currency: "₹", date: "12 Jul 2026", expenseCategory: "home"
            ),
            color: UIColor(red: 0.02, green: 0.23, blue: 0.48, alpha: 1),
            lines: ["IKEA", "", "BILLY bookcase  ₹6,990", "LACK table      ₹3,490", "FEJKA plant     ₹2,000", "", "TOTAL          ₹12,480"]
        ),
        Seed(
            title: "IndiGo BLR → DEL",
            extraction: ItemExtraction(
                category: "event", eventTitle: "Flight 6E 331 · BLR → DEL",
                eventStart: "Fri 14 Aug · 6:40 AM", eventLocation: "T1, Gate 14A"
            ),
            color: UIColor(red: 0.12, green: 0.13, blue: 0.25, alpha: 1),
            lines: ["INDIGO 6E 331", "", "BLR  →  DEL", "FRI 14 AUG · 6:40 AM", "GATE 14A · SEAT 12F"]
        ),
    ]

    private static func renderImage(color: UIColor, lines: [String]) -> Data? {
        let size = CGSize(width: 640, height: 900)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            lines.joined(separator: "\n").draw(
                in: CGRect(x: 48, y: 72, width: 544, height: 760),
                withAttributes: [
                    .font: UIFont.monospacedSystemFont(ofSize: 30, weight: .semibold),
                    .foregroundColor: UIColor.white
                ]
            )
        }
        return image.jpegData(compressionQuality: 0.85)
    }
}
#endif
