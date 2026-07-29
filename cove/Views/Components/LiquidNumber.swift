import SwiftUI

/// A figure set large and unboxed: the digits themselves are glass vessels
/// holding purple liquid, and the waterline sits wherever the caller says.
///
/// The `coveGlassNumber` shader is a layer effect, so it samples these glyphs
/// to find their own edges — see the shader for why that is what makes the
/// glass read as thick rather than as a flat fill.
///
/// Takes an already-formatted string rather than a number, because the two
/// places it appears want different things from the same treatment: Profile
/// shows a count in compact notation, Home shows money with a currency mark in
/// front of it. Formatting money is not this view's business.
struct LiquidNumber: View {
    let text: String
    /// 0 empty, 1 full.
    let level: Double
    var height: CGFloat = 208
    let accessibilityLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Faster than the page gradients — a small body of fluid in a held object
    /// should move at a hand's pace, not a horizon's.
    private static let period: Double = 7

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
        // GeometryReader has no intrinsic width. Explicitly claim the caller's
        // full width so the Metal layer receives a real canvas instead of the
        // near-zero proposal that made Home's currency figure disappear.
        .frame(maxWidth: .infinity)
        .frame(height: height)
        // Keeps the widest figure clear of the screen edges.
        .padding(.horizontal, 16)
        // Real glass sits on something. Without a shadow the digits float,
        // which reads as a sticker rather than as an object.
        .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }

    private func glyphs(loop: Float) -> some View {
        GeometryReader { geometry in
            Text(text)
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

    /// Point size chosen from how wide the figure actually is. `minimumScale
    /// Factor` alone would handle the overflow, but it shrinks the glyphs
    /// *within a fixed box* — the number would end up floating in dead space
    /// with the shader's wall thickness scaled for a size it is no longer
    /// drawn at. Choosing the size up front keeps the glass proportional.
    private var fontSize: CGFloat {
        switch text.count {
        case ...2: 186
        case 3: 156
        case 4: 130
        case 5: 112
        case 6: 100
        default: 88
        }
    }
}

#Preview("Liquid number") {
    ZStack {
        CoveInkBackground()
        VStack(spacing: 24) {
            LiquidNumber(text: "20", level: 1, accessibilityLabel: "20")
            LiquidNumber(text: "$100.55", level: 0.62, accessibilityLabel: "100 dollars 55")
        }
    }
}
