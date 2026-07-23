import SwiftData
import SwiftUI
import UIKit

struct ItemDetailView: View {
    let item: ShelfItem

    @State private var isShowingChat = false
    @State private var stubAction = ""
    @State private var isShowingStubAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero

                HStack(spacing: 8) {
                    Label(item.kind.label, systemImage: item.kind.systemImage)
                    Text(item.createdAt, format: .dateTime.day().month(.abbreviated).year())
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                if item.processingState == .processing || item.processingState == .queued {
                    HStack(spacing: 12) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Understanding this item")
                                .font(.headline)
                            Text("On-device models are reading, indexing, and summarizing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                }

                if item.processingState == .failed {
                    DetailPanel(title: "Processing failed", systemImage: "exclamationmark.triangle") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item.failureMessage ?? "Cove couldn’t process this item.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button {
                                let itemID = item.id
                                Task {
                                    await ShelfProcessor.shared.retry(itemID: itemID)
                                }
                            } label: {
                                Label("Try again", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }

                if let extraction = item.extraction, extractionRows(for: extraction) != nil {
                    DetailPanel(title: extractionTitle(for: extraction), systemImage: "doc.text.magnifyingglass") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(extractionRows(for: extraction) ?? [], id: \.0) { row in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(row.0)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 84, alignment: .leading)
                                    Text(row.1)
                                        .font(.callout)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }

                if let summary = item.summary {
                    DetailPanel(title: "Summary", systemImage: "sparkles") {
                        Text(summary)
                    }
                }

                if let note = item.userNote, item.kind != .text {
                    DetailPanel(title: "Your note", systemImage: "quote.bubble") {
                        Text(note)
                    }
                }

                if item.kind == .text, let note = item.userNote {
                    DetailPanel(title: "Note", systemImage: "note.text") {
                        Text(note)
                    }
                }

                if let extractedText = item.extractedText {
                    DetailPanel(title: "Extracted text", systemImage: "text.viewfinder") {
                        Text(extractedText)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }
                }

                if !item.tags.isEmpty {
                    DetailPanel(title: "Tags", systemImage: "tag") {
                        FlowLayout(spacing: 8) {
                            ForEach(item.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(.tint.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                }

                Button {
                    item.isInWallet.toggle()
                    try? item.modelContext?.save()
                } label: {
                    Label(
                        item.isInWallet ? "Remove from Wallet" : "Add to Wallet",
                        systemImage: item.isInWallet ? "wallet.pass.fill" : "wallet.pass"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                Button {
                    isShowingChat = true
                } label: {
                    Label("Chat about this", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)

                HStack {
                    stubButton("Add to Calendar", icon: "calendar.badge.plus")
                    stubButton("Add Reminder", icon: "checklist")
                }
            }
            .padding(16)
            .padding(.bottom, 20)
        }
        .background { CoveInkBackground() }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingChat) {
            ItemChatView(item: item)
        }
        .alert("UI scaffold only", isPresented: $isShowingStubAlert) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("\(stubAction) is intentionally not connected in Phase 1. Nothing was written outside Cove.")
        }
    }

    @ViewBuilder
    private var hero: some View {
        if let imageData = item.imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(maxHeight: 420)
                .clipShape(.rect(cornerRadius: 26))
        } else if let url = item.linkURL {
            Link(destination: url) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "safari")
                        .font(.system(size: 38))
                    Text(item.linkTitle ?? item.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.leading)
                    Text(item.linkHost ?? url.absoluteString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .glassEffect(.regular, in: .rect(cornerRadius: 26))
            }
            .buttonStyle(.plain)
        }
    }

    private func extractionTitle(for extraction: ItemExtraction) -> String {
        switch extraction.category {
        case "receipt": "Receipt"
        case "event": "Event"
        default: "Details"
        }
    }

    private func extractionRows(for extraction: ItemExtraction) -> [(String, String)]? {
        var rows: [(String, String)] = []
        switch extraction.category {
        case "receipt":
            if let merchant = extraction.merchant { rows.append(("Merchant", merchant)) }
            if let total = extraction.total {
                let currency = extraction.currency ?? ""
                rows.append(("Total", "\(currency)\(total)"))
            }
            if let date = extraction.date { rows.append(("Date", date)) }
            if let category = extraction.expenseCategory { rows.append(("Category", category)) }
        case "event":
            if let title = extraction.eventTitle { rows.append(("Event", title)) }
            if let start = extraction.eventStart { rows.append(("Starts", start)) }
            if let end = extraction.eventEnd { rows.append(("Ends", end)) }
            if let location = extraction.eventLocation { rows.append(("Where", location)) }
        default:
            return nil
        }
        return rows.isEmpty ? nil : rows
    }

    private func stubButton(_ title: String, icon: String) -> some View {
        Button {
            stubAction = title
            isShowingStubAlert = true
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .lineLimit(2)
        }
        .buttonStyle(.glass)
    }
}

private struct DetailPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: point.x + bounds.minX, y: point.y + bounds.minY),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? .infinity
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        var points: [CGPoint] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > width {
                cursor.x = 0
                cursor.y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(cursor)
            cursor.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return (CGSize(width: proposal.width ?? cursor.x, height: cursor.y + rowHeight), points)
    }
}
