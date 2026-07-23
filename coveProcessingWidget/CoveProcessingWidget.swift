import ActivityKit
import SwiftUI
import WidgetKit

@main
struct CoveProcessingWidgetBundle: WidgetBundle {
    var body: some Widget {
        CoveProcessingLiveActivity()
    }
}

struct CoveProcessingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CoveProcessingAttributes.self) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    activityIcon(for: context.state)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(activityTitle(for: context.state))
                            .font(.headline)
                        Text(context.state.latestTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                    statusBadge(for: context.state)
                }

                progressSection(for: context.state)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    activityIcon(for: context.state)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(activityTitle(for: context.state))
                            .font(.headline)
                        Text(context.state.latestTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    statusBadge(for: context.state)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    progressSection(for: context.state)
                }
            } compactLeading: {
                Image(systemName: phaseSymbol(for: context.state.phase))
                    .foregroundStyle(phaseColor(for: context.state.phase))
                    .accessibilityLabel(context.state.phase.label)
            } compactTrailing: {
                compactStatus(for: context.state)
            } minimal: {
                Image(systemName: phaseSymbol(for: context.state.phase))
                    .foregroundStyle(phaseColor(for: context.state.phase))
                    .accessibilityLabel(context.state.phase.label)
            }
        }
    }

    private func activityIcon(for state: CoveProcessingAttributes.ContentState) -> some View {
        let color = phaseColor(for: state.phase)
        return Image(systemName: phaseSymbol(for: state.phase))
            .font(.title2)
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.14), in: Circle())
            .accessibilityLabel(state.phase.label)
    }

    @ViewBuilder
    private func statusBadge(for state: CoveProcessingAttributes.ContentState) -> some View {
        switch state.phase {
        case .readyToCapture:
            Image(systemName: "plus")
                .accessibilityLabel("Ready to capture")
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("Saved")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("Processing failed")
        case .preparing, .recognizingText, .summarizing, .makingSearchable:
            if state.processingCount > 1 {
                Text("\(state.processingCount)")
                    .monospacedDigit()
                    .accessibilityLabel("\(state.processingCount) items processing")
            } else {
                percentage(for: state)
            }
        }
    }

    @ViewBuilder
    private func compactStatus(for state: CoveProcessingAttributes.ContentState) -> some View {
        switch state.phase {
        case .readyToCapture:
            Image(systemName: "plus")
        case .ready:
            Image(systemName: "checkmark")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark")
                .foregroundStyle(.orange)
        case .preparing, .recognizingText, .summarizing, .makingSearchable:
            if state.processingCount > 1 {
                Text("\(state.processingCount)")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } else {
                percentage(for: state)
            }
        }
    }

    @ViewBuilder
    private func progressSection(for state: CoveProcessingAttributes.ContentState) -> some View {
        if state.phase.isProcessing {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(state.phase.label)
                    Spacer()
                    if state.processingCount > 1 {
                        Text("\(state.processingCount) items")
                    } else {
                        Text(state.latestKind)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ProgressView(value: state.progress)
                    .tint(phaseColor(for: state.phase))
                    .animation(.smooth(duration: 0.35), value: state.progress)
            }
        } else {
            Label(state.phase.label, systemImage: phaseSymbol(for: state.phase))
                .font(.caption)
                .foregroundStyle(phaseColor(for: state.phase))
        }
    }

    private func percentage(for state: CoveProcessingAttributes.ContentState) -> some View {
        Text("\(Int((state.progress * 100).rounded()))")
            .font(.caption.bold())
            .monospacedDigit()
            .contentTransition(.numericText())
            .accessibilityLabel("\(Int((state.progress * 100).rounded())) percent complete")
    }

    private func activityTitle(for state: CoveProcessingAttributes.ContentState) -> String {
        switch state.phase {
        case .readyToCapture: "Cove is ready"
        case .preparing, .recognizingText, .summarizing, .makingSearchable: "Cove is filing"
        case .ready: "Saved to Cove"
        case .failed: "Cove needs attention"
        }
    }

    private func phaseSymbol(for phase: CoveProcessingPhase) -> String {
        switch phase {
        case .readyToCapture: "square.stack.3d.up.fill"
        case .preparing: "photo.badge.arrow.down"
        case .recognizingText: "text.viewfinder"
        case .summarizing: "text.line.3.summary"
        case .makingSearchable: "sparkle.magnifyingglass"
        case .ready: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func phaseColor(for phase: CoveProcessingPhase) -> Color {
        switch phase {
        case .ready: .green
        case .failed: .orange
        case .readyToCapture, .preparing, .recognizingText, .summarizing, .makingSearchable: .cyan
        }
    }
}
