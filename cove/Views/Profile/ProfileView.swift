import SwiftData
import SwiftUI

/// Profile tab. Cove has no account system — the name is stored locally and
/// exists so the shelf feels like *yours*, not so anything can be signed into.
///
/// The page is built around one idea Liquid Glass can do that a blur cannot:
/// glass shapes that **merge and split**. The shelf's categories are pebbles
/// sized by how much each holds, floating in a single `GlassEffectContainer`
/// so neighbours fuse where they crowd each other. Tapping one morphs that
/// pebble — the same glass, not a crossfade — into the panel that describes
/// it, and tapping away lets it fall back into the cluster.
///
/// It all sits on Cove's flat cream. Glass reads more quietly there than it
/// did over the gradient this replaced: with nothing behind it to refract, the
/// material falls back to a soft tint and its edge highlight, so the pebbles'
/// *sizes* carry the page rather than their surface.
struct ProfileView: View {
    var onOpenShelf: () -> Void = {}
    var onOpenWallet: () -> Void = {}

    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]
    @State private var categorizer = ShelfCategorizer.shared
    @State private var importer = GalleryImporter.shared

    /// Stamped the first time this screen is opened. Deliberately *not* derived
    /// from the oldest item: imported screenshots carry the photo's own date, so
    /// that would claim you'd been using Cove since whenever you took them.
    @AppStorage("profileStartedAt") private var startedAt: Double = 0

    /// Which pebble is currently expanded, if any.
    @State private var openBucket: ShelfBucket?
    /// Shared by every glass shape on the page, so they can morph into one
    /// another rather than fade.
    @Namespace private var glass

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                CoveInkBackground()
                    // Tapping the backdrop is how you close an open pebble.
                    .contentShape(.rect)
                    .onTapGesture { close() }

                ScrollView {
                    VStack(spacing: 26) {
                        hero
                        cluster
                        footer
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 36)
                }
                .scrollIndicators(.hidden)
                .safeAreaBar(edge: .top) {
                    topBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 6)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                // The floating dock is its own glass; no wash under it.
                .scrollEdgeEffectHidden(true, for: .bottom)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            if startedAt == 0 { startedAt = Date.now.timeIntervalSince1970 }
        }
    }

    // MARK: - Derived

    private var buckets: [(bucket: ShelfBucket, items: [ShelfItem])] {
        categorizer.group(items)
    }

    private var largestBucket: Int {
        max(buckets.map(\.items.count).max() ?? 1, 1)
    }

    private var unfinishedCount: Int {
        items.filter { $0.processingState != .ready }.count
    }

    private func count(of state: ShelfProcessingState) -> Int {
        items.filter { $0.processingState == state }.count
    }

    /// Pictures Cove has finished putting through the pipeline — the headline
    /// number. Notes and links are excluded: they never needed indexing in the
    /// first place, so counting them would flatter the figure.
    private var indexedImageCount: Int {
        items.filter {
            ($0.kind == .image || $0.kind == .screenshot) && $0.processingState == .ready
        }
        .count
    }

    private var totalImageCount: Int {
        items.filter { $0.kind == .image || $0.kind == .screenshot }.count
    }

    /// How full the liquid sits: the share of pictures that are done. An empty
    /// library reads as full rather than empty — there is nothing left to do.
    private var indexedFraction: Double {
        guard totalImageCount > 0 else { return 1 }
        return Double(indexedImageCount) / Double(totalImageCount)
    }

    private var memberSince: String? {
        guard startedAt > 0 else { return nil }
        return Date(timeIntervalSince1970: startedAt)
            .formatted(.dateTime.month(.abbreviated).year())
    }

    /// Buckets in rows of three, biggest first — the cluster reads as a heap
    /// with the heavy pebbles leading.
    private var pebbleRows: [[(bucket: ShelfBucket, items: [ShelfItem])]] {
        let sorted = buckets.sorted { $0.items.count > $1.items.count }
        return stride(from: 0, to: sorted.count, by: 3).map {
            Array(sorted[$0..<min($0 + 3, sorted.count)])
        }
    }

    private static let morph = Animation.spring(response: 0.44, dampingFraction: 0.8)

    private func open(_ bucket: ShelfBucket) {
        withAnimation(Self.morph) { openBucket = bucket }
    }

    private func close() {
        guard openBucket != nil else { return }
        withAnimation(Self.morph) { openBucket = nil }
    }

    // MARK: - Chrome

    private var topBar: some View {
        CoveScreenHeader("Profile") {
#if DEBUG
            NavigationLink {
                AIDiagnosticsView()
            } label: {
                CoveHeaderIcon(systemImage: "stethoscope")
            }
            .accessibilityLabel("AI diagnostics")
#endif
        } trailing: {
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                CoveHeaderIcon(systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("System settings")
        }
    }

    // MARK: - Hero

    /// Avatar and name, with the item count set as a lens directly over the
    /// gradient rather than boxed in a card.
    private var hero: some View {
        VStack(spacing: 0) {
            LiquidCount(value: indexedImageCount, level: indexedFraction)
                .padding(.top, 18)

            Text("Files indexed")
                .font(.system(size: 13, weight: .semibold))
                .tracking(2.2)
                .textCase(.uppercase)
                .foregroundStyle(CoveTheme.ink.opacity(0.5))
                .padding(.top, 6)

            Text(subtitleLine)
                .font(.footnote)
                .foregroundStyle(CoveTheme.ink.opacity(0.42))
                .padding(.top, 6)
        }
    }

    private var subtitleLine: String {
        var parts = ["\(items.count) saved"]
        if let memberSince { parts.append("since \(memberSince)") }
        if unfinishedCount > 0 { parts.append("\(unfinishedCount) working") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Pebble cluster

    /// One container for the whole cluster, so pebbles that crowd each other
    /// fuse at the edges instead of overlapping as separate panes — and so an
    /// opening pebble morphs out of the group rather than appearing over it.
    private var cluster: some View {
        GlassEffectContainer(spacing: 20) {
            if let openBucket, let group = buckets.first(where: { $0.bucket == openBucket }) {
                bucketPanel(bucket: group.bucket, count: group.items.count)
                    // Shares an ID with the pebble it came from, so the glass
                    // itself travels and re-shapes from that circle rather
                    // than a new panel appearing over the cluster.
                    .glassEffectID(group.bucket.rawValue, in: glass)
                    .transition(.opacity)
            } else if buckets.isEmpty {
                emptyPebble
            } else {
                VStack(spacing: 16) {
                    ForEach(Array(pebbleRows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .center, spacing: 16) {
                            ForEach(row, id: \.bucket.id) { group in
                                pebble(bucket: group.bucket, count: group.items.count)
                                    .glassEffectID(group.bucket.rawValue, in: glass)
                                    // The others shrink away rather than
                                    // blinking out, so the eye can follow the
                                    // one that is expanding.
                                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Self.morph, value: openBucket)
        // Categorising runs after launch, so the set of buckets can change
        // under an open panel. Without this the panel's bucket could vanish
        // from the list and the page would sit on a branch that renders
        // nothing — reading as a pebble that refused to open.
        .onChange(of: buckets.map(\.bucket)) { _, current in
            if let openBucket, !current.contains(openBucket) {
                self.openBucket = nil
            }
        }
    }

    /// Diameter carries the count, so the cluster is a chart as well as a menu
    /// — the shape of your shelf is visible before you read a single label.
    private func diameter(for count: Int) -> CGFloat {
        let share = Double(count) / Double(largestBucket)
        return 62 + 46 * share
    }

    private func pebble(bucket: ShelfBucket, count: Int) -> some View {
        let size = diameter(for: count)

        return Button {
            open(bucket)
        } label: {
            VStack(spacing: size * 0.015) {
                Image(systemName: bucket.systemImage)
                    .font(.system(size: size * 0.21, weight: .medium))
                    .foregroundStyle(bucket.tint)
                    .frame(height: size * 0.26)

                Text("\(count)")
                    .font(.system(size: size * 0.27, weight: .semibold, design: .serif).monospacedDigit())
                    .foregroundStyle(CoveTheme.ink)
                    .frame(height: size * 0.30)
            }
            .frame(width: size, height: size)
            .glassEffect(.regular.interactive(), in: Circle())
            // Without this the button only hit-tests the icon and number, so
            // taps anywhere on the surrounding ring — most of the pebble —
            // silently did nothing. That was the "sometimes won't open".
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(bucket.label), \(count) items")
        .accessibilityHint("Opens details")
    }

    /// The cluster's resting state when there is nothing to show yet.
    private var emptyPebble: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.title2.weight(.medium))
                .foregroundStyle(CoveTheme.ink.opacity(0.5))
            Text("Nothing saved yet")
                .font(.footnote.weight(.medium))
                .foregroundStyle(CoveTheme.ink.opacity(0.55))
        }
        .frame(width: 150, height: 150)
        .glassEffect(.regular, in: Circle())
    }

    /// What the pebble becomes. Same glass, re-shaped — the morph is the whole
    /// point of routing both through one `glassEffectID`.
    private func bucketPanel(bucket: ShelfBucket, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: bucket.systemImage)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(bucket.tint)
                    .frame(width: 44, height: 44)
                    .background(bucket.tint.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(bucket.label)
                        .font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(CoveTheme.ink)
                    Text("\(count) of \(items.count) items")
                        .font(.caption)
                        .foregroundStyle(CoveTheme.ink.opacity(0.55))
                }

                Spacer(minLength: 0)

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(CoveTheme.ink.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            // Share of the shelf, as a glass-lensed bar.
            ProgressView(value: Double(count), total: Double(max(items.count, 1)))
                .tint(bucket.tint)

            HStack(spacing: 10) {
                Button {
                    close()
                    bucket == .receipts || bucket == .events ? onOpenWallet() : onOpenShelf()
                } label: {
                    Label(
                        bucket == .receipts || bucket == .events ? "Open wallet" : "Open shelf",
                        systemImage: "arrow.up.right"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glass)
                .tint(CoveTheme.ink)

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    // MARK: - Footer

    /// The two things worth doing from here, plus the promise the app is built
    /// on. Unioned so the row reads as one piece of glass with a seam, not as
    /// separate buttons.
    private var footer: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.subheadline)
                        .foregroundStyle(CoveTheme.ink.opacity(0.7))

                    Text("Extraction, categorising, and search all run here. Nothing you save is uploaded.")
                        .font(.footnote)
                        .foregroundStyle(CoveTheme.ink.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))

                libraryControl
            }
        }
    }

    @ViewBuilder
    private var libraryControl: some View {
        if importer.isDenied {
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                footerRow("Photo access is off", detail: "Turn it on", systemImage: "exclamationmark.triangle")
            }
            .buttonStyle(.plain)
        } else if importer.isImporting {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Indexing · \(importer.importedCount)/\(importer.totalCount)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CoveTheme.ink)
                Spacer(minLength: 0)
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            Button {
                Task { await importer.importLibrary() }
            } label: {
                footerRow(
                    "Re-scan library",
                    detail: versionLabel,
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func footerRow(_ title: String, detail: String?, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CoveTheme.ink.opacity(0.75))
                .frame(width: 22)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CoveTheme.ink)

            Spacer(minLength: 0)

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(CoveTheme.ink.opacity(0.45))
            }
        }
        .padding(16)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
    }

    private var versionLabel: String? {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return "Cove \(version)"
    }
}

// MARK: - Liquid count

/// The headline figure, set large and unboxed: the digits themselves are glass
/// vessels holding purple liquid, and the waterline sits where indexing has
/// got to, rising as the pipeline works through the library.
///
/// The `coveGlassNumber` shader is a layer effect, so it samples these glyphs
/// to find their own edges — see the shader for why that is what makes the
/// glass read as thick rather than as a flat fill.
private struct LiquidCount: View {
    let value: Int
    /// 0 empty, 1 full.
    let level: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Faster than the page gradients — a small body of fluid in a held object
    /// should move at a hand's pace, not a horizon's.
    private static let period: Double = 7
    private static let height: CGFloat = 208

    var body: some View {
        Group {
            if reduceMotion {
                glyphs(loop: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let loop = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: Self.period) / Self.period
                    glyphs(loop: Float(loop))
                }
            }
        }
        .frame(height: Self.height)
        // Keeps the widest figure clear of the screen edges.
        .padding(.horizontal, 16)
        // Real glass sits on something. Without a shadow the digits float,
        // which reads as a sticker rather than as an object.
        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
        .accessibilityElement()
        .accessibilityLabel("\(value) pictures indexed")
    }

    private func glyphs(loop: Float) -> some View {
        GeometryReader { geometry in
            Text(formatted)
                .font(.system(size: fontSize, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .layerEffect(
                    ShaderLibrary.coveGlassNumber(
                        .float2(geometry.size),
                        .float(loop),
                        .float(Float(min(max(level, 0), 1)))
                    ),
                    // Must clear the widest ring the shader reads. The wall
                    // scales with glyph height and is capped at 16pt there, so
                    // this has to stay above that cap.
                    maxSampleOffset: CGSize(width: 22, height: 22)
                )
        }
    }

    /// Compact notation, so a large library reads "12.4K" rather than running
    /// off the side of the screen.
    private var formatted: String {
        value.formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(0...1))
        )
    }

    /// Point size chosen from how wide the figure actually is. `minimumScale
    /// Factor` alone would handle the overflow, but it shrinks the glyphs
    /// *within a fixed box* — the number would end up floating in dead space
    /// with the shader's wall thickness scaled for a size it is no longer
    /// drawn at. Choosing the size up front keeps the glass proportional.
    private var fontSize: CGFloat {
        switch formatted.count {
        case ...2: 186
        case 3: 156
        case 4: 130
        case 5: 112
        default: 96
        }
    }
}

#Preview("Profile") {
    ProfileView()
        .modelContainer(for: ShelfItem.self, inMemory: true)
        .environment(\.aiServices, .mock)
}
