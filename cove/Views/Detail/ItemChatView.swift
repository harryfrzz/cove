import SwiftUI
import UIKit

struct ItemChatView: View {
    let item: ShelfItem

    @Environment(\.aiServices) private var aiServices
    @Environment(\.dismiss) private var dismiss
    @State private var question = "What should I remember?"
    @State private var answer: String?
    @State private var isAnswering = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.headline)
                    Text("This is a mock chat surface. No model or network request runs in Phase 1.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))

                if let answer {
                    Text(answer)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                } else {
                    Spacer()
                }

                HStack(spacing: 10) {
                    TextField("Ask about this item", text: $question)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: Capsule())

                    Button(action: ask) {
                        if isAnswering {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnswering)
                }
            }
            .padding(16)
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func ask() {
        isAnswering = true
        answer = nil

        Task {
            defer { isAnswering = false }
            if let imageData = item.imageData, let image = UIImage(data: imageData) {
                answer = try? await aiServices.imageUnderstanding.answer(question: question, about: image)
            } else {
                try? await Task.sleep(for: .milliseconds(480))
                answer = "Mock answer: \(item.summary ?? "this item is saved locally and ready to revisit.")"
            }
        }
    }
}
