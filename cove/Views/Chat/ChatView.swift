import FoundationModels
import SwiftData
import SwiftUI

/// One turn in the conversation. Kept as a value type so the transcript is
/// plain view state — the model session below owns the *real* history, this
/// array only owns what is drawn.
struct ChatMessage: Identifiable, Equatable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    var text: String
}

/// Ask-your-shelf surface. Deliberately plain for now: a transcript, an input
/// bar, and the on-device model behind it. No tool calls, no citations, no
/// per-item threading — those are the things that will want design attention,
/// so the frame they land in stays simple until then.
///
/// Answers come from Apple's Foundation Models, the same system model the
/// extraction pipeline uses, primed with a short digest of what is on the
/// shelf. Nothing leaves the device, so an unavailable model is a normal
/// state here rather than an error — it gets its own banner.
struct ChatView: View {
    @Query(sort: \ShelfItem.createdAt, order: .reverse) private var items: [ShelfItem]

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isResponding = false
    /// Holds the transcript, so follow-up questions know what was already
    /// asked. Built on the first send, cleared when the transcript is.
    @State private var session: LanguageModelSession?
    @State private var unavailable: FoundationModelsService.ModelUnavailable?

    @FocusState private var isInputFocused: Bool

    /// How much of the shelf is described to the model. The system model's
    /// context window is small and shared with the instructions, so this is a
    /// digest of the most recent items rather than the whole library.
    private static let contextItemLimit = 12

    var body: some View {
        VStack(spacing: 0) {
            transcript
            // Explicit row rather than a bottom safe-area inset: the shell
            // already spends that slot on the floating dock, and a second one
            // underneath it never drew.
            inputBar
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, CoveTabBar.occupiedHeight)
        }
        .background(CoveInkBackground())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            unavailable = FoundationModelsService.availabilityError()
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let unavailable {
                        unavailableBanner(unavailable)
                    }

                    if messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(messages) { message in
                            bubble(message)
                        }
                    }

                    if isResponding {
                        thinkingBubble
                    }

                    // Scroll anchor: sized so the last bubble clears the input
                    // bar rather than sitting flush against it.
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages) { _, _ in scrollToBottom(proxy) }
            .onChange(of: isResponding) { _, _ in scrollToBottom(proxy) }
        }
        .safeAreaBar(edge: .top) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private static let bottomAnchor = "coveChatBottom"

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
        }
    }

    // MARK: - Chrome

    /// Same header every other tab wears. Starting a fresh conversation only
    /// appears once there is one to discard.
    private var topBar: some View {
        CoveScreenHeader("Chat") {
            if !messages.isEmpty {
                Button(action: clear) {
                    CoveHeaderIcon(systemImage: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New conversation")
            }
        }
    }

    // MARK: - Transcript

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        let body = Text(message.text)
            .font(.callout)
            .foregroundStyle(message.role == .user ? CoveTheme.background : CoveTheme.ink)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

        HStack {
            if message.role == .user {
                Spacer(minLength: 44)
                // Solid ink for what you said, glass for what came back — the
                // same split the dock draws between the one action and the
                // destinations beside it.
                body.background(CoveTheme.ink, in: .rect(cornerRadius: 20))
            } else {
                body.glassEffect(.regular, in: .rect(cornerRadius: 20))
                Spacer(minLength: 44)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var thinkingBubble: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Thinking")
                .font(.callout)
                .foregroundStyle(CoveTheme.inkSecondary)
            Spacer(minLength: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask about anything on your shelf.")
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(CoveTheme.ink)

            Text("Answers are drawn from your saved items and stay on this device.")
                .font(.footnote)
                .foregroundStyle(CoveTheme.inkSecondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button {
                        draft = suggestion
                        send()
                    } label: {
                        HStack(spacing: 8) {
                            Text(suggestion)
                                .font(.subheadline)
                                .foregroundStyle(CoveTheme.ink)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(CoveTheme.ink.opacity(0.4))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .disabled(unavailable != nil)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 24)
    }

    private static let suggestions = [
        "What do I have coming up?",
        "How much did I spend recently?",
        "Find the ticket with my seat number."
    ]

    // MARK: - Unavailable

    private func unavailableBanner(_ reason: FoundationModelsService.ModelUnavailable) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)

            Text(reason.errorDescription ?? "The on-device model is unavailable.")
                .font(.footnote)
                .foregroundStyle(CoveTheme.ink.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask Cove", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .font(.callout)
                .foregroundStyle(CoveTheme.ink)
                .focused($isInputFocused)
                .submitLabel(.send)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .glassEffect(.regular.interactive(), in: Capsule())
                .disabled(unavailable != nil)

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CoveTheme.background)
                    .frame(width: 42, height: 42)
                    .background(CoveTheme.ink.opacity(canSend ? 1 : 0.25), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isResponding
            && unavailable == nil
    }

    // MARK: - Sending

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isResponding, unavailable == nil else { return }

        draft = ""
        withAnimation(.easeOut(duration: 0.2)) {
            messages.append(ChatMessage(role: .user, text: question))
            isResponding = true
        }

        Task {
            defer { isResponding = false }

            // Re-checked per send: Apple Intelligence can be switched off
            // while the app is open, which would otherwise surface as a
            // generic failure inside a bubble.
            if let reason = FoundationModelsService.availabilityError() {
                unavailable = reason
                return
            }

            let active = session ?? LanguageModelSession(instructions: instructions)
            session = active

            do {
                let response = try await active.respond(to: question)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                withAnimation(.easeOut(duration: 0.2)) {
                    messages.append(
                        ChatMessage(
                            role: .assistant,
                            text: text.isEmpty ? "I don't have an answer for that yet." : text
                        )
                    )
                }
            } catch {
                withAnimation(.easeOut(duration: 0.2)) {
                    messages.append(
                        ChatMessage(
                            role: .assistant,
                            text: "That didn't go through — \(error.localizedDescription)"
                        )
                    )
                }
            }
        }
    }

    private func clear() {
        withAnimation(.easeOut(duration: 0.2)) {
            messages.removeAll()
        }
        session = nil
        unavailable = FoundationModelsService.availabilityError()
    }

    /// The shelf digest the session is primed with. Built once per session so
    /// the transcript stays consistent with what the model was told, even if
    /// the pipeline finishes more items mid-conversation.
    private var instructions: String {
        """
        You are Cove, an assistant for a personal shelf of saved screenshots, \
        tickets, receipts, links, and notes. Answer in one or two short \
        sentences. Use the saved items below when they are relevant, and say \
        you cannot find it rather than inventing details.

        Saved items:
        \(shelfDigest)
        """
    }

    private var shelfDigest: String {
        let lines = items
            .filter { $0.processingState == .ready }
            .prefix(Self.contextItemLimit)
            .map { item -> String in
                let detail = item.summary
                    ?? item.extraction?.shortTitle
                    ?? item.kind.label
                return "- \(item.title): \(detail)"
            }
        return lines.isEmpty ? "(nothing saved yet)" : lines.joined(separator: "\n")
    }
}

#Preview("Chat") {
    ChatView()
        .modelContainer(for: ShelfItem.self, inMemory: true)
        .environment(\.aiServices, .mock)
}
