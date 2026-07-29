import SwiftUI

struct CoveBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            if reduceMotion {
                shaderSurface(size: geometry.size, time: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 120)
                    shaderSurface(size: geometry.size, time: Float(time))
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func shaderSurface(size: CGSize, time: Float) -> some View {
        Rectangle()
            .fill(.black)
            .colorEffect(
                ShaderLibrary.coveFlow(
                    .float(time),
                    .float2(size)
                )
            )
    }
}

// MARK: - Seeded flowing gradient

/// A living gradient surface drawn by the `coveEventFlow` fragment shader:
/// three coloured lights orbiting through a warped space. Used behind the
/// Upcoming cards and the profile hero.
///
/// Reduce Motion pins it to a single frame — this is decoration, and continuous
/// background movement is exactly what that setting exists to stop.
struct CoveGradientBackdrop: View {
    let palette: CoveGradientPalette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds for one full turn of the animation. Every term in the shader is
    /// an integer harmonic of this, so the pattern returns exactly to its
    /// starting state and repeats forever without a seam.
    private static let period: Double = 48

    var body: some View {
        GeometryReader { geometry in
            if reduceMotion {
                // Offset per surface, so several frozen cards still show
                // distinct compositions instead of the same frame repeated.
                surface(size: geometry.size, loop: palette.phase)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    // A 0…1 phase, not a clock. Wrapping here is safe because
                    // the shader is periodic in exactly this value — and it
                    // keeps the uniform small, where a raw reference-date
                    // interval would have lost enough Float precision to
                    // quantise the motion into visible steps.
                    let loop = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: Self.period) / Self.period
                    surface(size: geometry.size, loop: Float(loop))
                }
            }
        }
    }

    private func surface(size: CGSize, loop: Float) -> some View {
        Rectangle()
            .fill(.black)
            .colorEffect(
                ShaderLibrary.coveEventFlow(
                    .float2(size),
                    .float(loop),
                    .float4(palette.driftingHue(at: loop), palette.spread, palette.saturation, palette.valueStep),
                    .float4(palette.phase, palette.spin, palette.ratio, palette.warp),
                    .float4(palette.falloff, palette.radius, palette.harmonic, palette.hueTurns)
                )
            )
    }
}

/// Everything that makes one gradient surface look and move like itself.
/// Colour and motion are both rolled here — two surfaces differ in palette
/// *and* in the shape and direction of their flow, not just in where they
/// start.
///
/// All of it is derived from a UUID rather than rolled at random. A fresh roll
/// per render would strobe as a carousel recycles cells, and would repaint the
/// same item after every relaunch — the point is that a card is recognisably
/// *its* card.
///
/// `Hasher` is deliberately avoided: Swift salts it per process, so it would
/// not survive a relaunch either.
struct CoveGradientPalette {
    /// Where the palette sits on the wheel at rest.
    var hue: Float
    /// Which of the anchor families this surface sits on.
    var anchorIndex: Int
    /// Arc between the three stops. Low is near-monochrome, high throws them
    /// apart into complementary territory — the main source of variety.
    var spread: Float
    let saturation: Float
    /// Brightness step between stops.
    let valueStep: Float

    /// Starting angle, de-syncing this surface from the others.
    let phase: Float
    /// Direction only, ±1. Rate lives in `harmonic`, because a fractional
    /// rate would stop the animation from closing back on itself.
    let spin: Float
    /// Vertical swings per horizontal one — ellipse, figure-eight, trefoil.
    /// Whole numbers only: a fractional ratio traces a curve that never
    /// closes, which would break the loop.
    let ratio: Float
    /// Turbulence of the domain warp.
    let warp: Float

    /// Blob definition: low is a soft wash, high is three distinct lights.
    let falloff: Float
    /// How much of the surface each light sweeps.
    let radius: Float
    /// Orbits completed per loop by the first light; the other two take the
    /// next harmonics up. This is what varies the *speed* between surfaces.
    let harmonic: Float
    /// Whole turns of the colour wheel per loop. Zero holds the palette still.
    var hueTurns: Float

    /// Motion is always rolled from the seed; the colour parameters can be
    /// pinned instead, for a surface that wants a chosen identity rather than
    /// whatever its seed happened to land on.
    ///
    /// - Parameters:
    ///   - family: index into the anchor families, wrapped. Pass the surface's
    ///     position in its row to guarantee no two on screen share a colour —
    ///     a rolled family collides roughly a quarter of the time with only
    ///     four to choose from, and two identical cards side by side is exactly
    ///     what the anchors exist to prevent.
    ///   - hue: starting point on the wheel. Overrides `family`.
    ///   - spread: how far the three stops sit apart.
    ///   - hueTurns: pass `0` to hold the palette still. Without it a rolled
    ///     value of 1 rotates the whole wheel every loop, so a chosen `hue`
    ///     only decides where the rotation *starts* — the surface still spends
    ///     most of its time some other colour entirely.
    init(
        seed id: UUID,
        family chosenFamily: Int? = nil,
        hue chosenHue: Float? = nil,
        spread chosenSpread: Float? = nil,
        hueTurns chosenTurns: Float? = nil
    ) {
        var generator = SeededRandom(Self.mix(id))
        func roll(_ lower: Float, _ upper: Float) -> Float {
            lower + Float(generator.next()) * (upper - lower)
        }
        /// Whole number in `0..<count`.
        func pick(_ count: Int) -> Float {
            Float(min(Int(generator.next() * Double(count)), count - 1))
        }

        // Anchored, not free. Rolling the hue across the whole wheel gave every
        // card an unrelated colour, and a page of them read as noise. Four
        // fixed families keep the set coherent while still telling cards apart.
        anchorIndex = Int(pick(Self.hueAnchors.count))
        hue = Self.hueAnchors[anchorIndex]
        // Tight. The shader lays the three stops at hue, hue+spread and
        // hue+2·spread, so the *span* is double whatever goes here — at the old
        // 0.16 a card covered a third of the wheel by itself and drifted well
        // off the family it was anchored to.
        spread = roll(0.03, 0.08)
        // Pastel, to sit with the wallet's ticket stock rather than shouting
        // over it.
        saturation = roll(0.16, 0.30)
        valueStep = roll(0.02, 0.10)

        phase = roll(0, 1)
        spin = generator.next() < 0.5 ? -1 : 1
        ratio = 1 + pick(3)
        warp = roll(0.06, 0.19)

        falloff = roll(9, 20)
        radius = roll(0.30, 0.46)
        harmonic = 1 + pick(3)
        // The shader's own sweep stays off — it walks the *whole* wheel, which
        // is what made the page look like a paint box. What movement the colour
        // has comes from `driftingHue(at:)` instead, and never leaves the
        // family this surface was anchored to.
        hueTurns = 0

        // Rolled above regardless, so pinning the family leaves the motion this
        // seed produces untouched.
        if let chosenFamily {
            anchorIndex = ((chosenFamily % Self.hueAnchors.count) + Self.hueAnchors.count)
                % Self.hueAnchors.count
            hue = Self.hueAnchors[anchorIndex]
        }
        if let chosenHue { hue = chosenHue }
        if let chosenSpread { spread = chosenSpread }
        if let chosenTurns { hueTurns = chosenTurns }
    }

    /// The families a card can land on, as positions on the colour wheel.
    /// Matched to the wallet's ticket stock — lime, mint, periwinkle, lavender
    /// — so Upcoming and the passes read as one palette instead of two. There
    /// are exactly as many of these as `HomeDashboardView` shows event cards,
    /// so pinning each card to its position gives every one its own family.
    private static let hueAnchors: [Float] = [0.22, 0.44, 0.66, 0.80]

    /// How far either side of its anchor a surface's hue travels, as a fraction
    /// of the wheel. Small on purpose: this is the difference between a card
    /// that breathes and a card that changes colour on you. Anything past about
    /// `0.03` starts crossing into the neighbouring family.
    private static let drift: Float = 0.014

    /// Where this surface's colour sits at a point in the loop.
    ///
    /// A slow sway either side of the card's own anchor, never a walk between
    /// them — a card keeps the colour it opened with, and what moves is the
    /// light rather than the identity. `phase` de-syncs the sway from the other
    /// cards, and being a whole sine over `loop` it closes back on itself
    /// exactly like the rest of the animation.
    func driftingHue(at loop: Float) -> Float {
        hue + sin((loop + phase) * 2 * .pi) * Self.drift
    }

    /// splitmix64 finalizer over the raw UUID bytes. The avalanche matters —
    /// a plain byte fold left neighbouring cards landing on the same hue.
    private static func mix(_ id: UUID) -> UInt64 {
        let folded = withUnsafeBytes(of: id.uuid) { bytes in
            bytes.reduce(UInt64(5_381)) { ($0 &* 33) &+ UInt64($1) }
        }
        var z = folded &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// xorshift64, so the same UUID always paints the same surface. Deterministic
/// and tiny is the whole requirement — this is decoration, not anything that
/// needs to be unpredictable.
private struct SeededRandom {
    private var state: UInt64

    init(_ seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    /// Next value in `0..<1`, taking the high bits — the low bits of an
    /// xorshift are the weakest part of its output.
    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }
}
