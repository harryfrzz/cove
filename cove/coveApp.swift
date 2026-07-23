//
//  coveApp.swift
//  cove
//
//  Created by Harikrishna C on 22/07/26.
//

import SwiftUI
import SwiftData
#if DEBUG
import AppIntents
import UIKit
import UniformTypeIdentifiers
#endif

@main
struct coveApp: App {
    init() {
#if DEBUG
        Task { @MainActor in
            WalletSeeder.seedIfRequested()
        }

        guard ProcessInfo.processInfo.arguments.contains("--verify-screenshot-intent") else {
            return
        }

        Task { @MainActor in
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 1_200))
            let image = renderer.image { context in
                UIColor(red: 0.03, green: 0.12, blue: 0.2, alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 600, height: 1_200))
                let text = "COVE SCREENSHOT TEST\nReceipt #2048\nCoffee  ₹240\nTotal  ₹240"
                text.draw(
                    at: CGPoint(x: 48, y: 120),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 34, weight: .semibold),
                        .foregroundColor: UIColor.white
                    ]
                )
            }
            guard let data = image.pngData() else { return }

            var intent = ProcessScreenshotIntent()
            intent.screenshot = IntentFile(data: data, filename: "cove-test.png", type: .png)
            _ = try? await intent.perform()
        }
#endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.aiServices, .current)
                .task {
                    // Recover items stranded mid-processing by a kill and
                    // re-index embeddings written by an older model version.
                    await ShelfProcessor.shared.reconcileAtLaunch()
                }
        }
        .modelContainer(CoveStore.shared)
    }
}
