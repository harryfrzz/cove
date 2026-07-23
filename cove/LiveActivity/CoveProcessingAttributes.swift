import ActivityKit
import Foundation

enum CoveProcessingPhase: String, Codable, Hashable {
    case readyToCapture
    case preparing
    case recognizingText
    case summarizing
    case makingSearchable
    case ready
    case failed

    var label: String {
        switch self {
        case .readyToCapture: "Ready to capture"
        case .preparing: "Preparing screenshot"
        case .recognizingText: "Reading text"
        case .summarizing: "Summarizing"
        case .makingSearchable: "Making it searchable"
        case .ready: "Saved to Cove"
        case .failed: "Couldn’t process"
        }
    }

    var isProcessing: Bool {
        switch self {
        case .preparing, .recognizingText, .summarizing, .makingSearchable:
            true
        case .readyToCapture, .ready, .failed:
            false
        }
    }
}

struct CoveProcessingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var processingCount: Int
        var latestTitle: String
        var latestKind: String
        var phase: CoveProcessingPhase
        var progress: Double
    }

    var sessionID: UUID
}
