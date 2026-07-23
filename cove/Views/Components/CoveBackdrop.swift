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
