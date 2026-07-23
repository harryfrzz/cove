import SwiftUI
import UIKit

struct ShelfCard: View {
    let item: ShelfItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            thumbnail
                .frame(maxWidth: .infinity)
                .frame(height: 132)
                .clipShape(.rect(cornerRadius: 18))

            HStack(spacing: 8) {
                Label(item.kind.label, systemImage: item.kind.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if item.processingState == .processing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Processing")
                }
            }

            Text(item.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if item.imageData != nil {
            ShelfThumbnail(item: item)
        } else {
            ZStack {
                LinearGradient(
                    colors: [.indigo.opacity(0.6), .cyan.opacity(0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}
