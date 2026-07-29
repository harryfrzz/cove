import SwiftUI

/// The four root destinations Cove switches between. Titles exist only for
/// VoiceOver — the bar itself is deliberately icon-only.
///
/// Search has no tab of its own: it lives in Home's screenshot library, so
/// finding something happens where the things already are.
enum CoveTab: String, CaseIterable, Identifiable {
    case home
    case wallet
    case upcoming
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .wallet: "Wallet"
        case .upcoming: "Upcoming"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .wallet: "wallet.pass"
        case .upcoming: "calendar"
        case .profile: "person.crop.circle"
        }
    }

    /// Filled counterpart used while the tab is active.
    var selectedSystemImage: String {
        switch self {
        case .home: "house.fill"
        case .wallet: "wallet.pass.fill"
        case .upcoming: "calendar.circle.fill"
        case .profile: "person.crop.circle.fill"
        }
    }
}

/// Floating dock: one Liquid Glass pill holding every destination, with the
/// capture button standing free at the trailing end. Keeping the plus off the
/// pill is deliberate — navigation and the one action are different kinds of
/// control, and a separate button can never be mistaken for another tab. Both
/// live in one `GlassEffectContainer` so their glass samples as one surface.
struct CoveTabBar: View {
    @Binding var selection: CoveTab
    var onCamera: () -> Void = {}
    var onAdd: (AddCaptureMode) -> Void = { _ in }
    var onAIPrompt: @MainActor (String) async -> String = { _ in "" }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator
    @Namespace private var dockMorph
    @State private var isInputExpanded = false
    @State private var inputSourceTab: CoveTab?
    @State private var promptText = ""
    @State private var submittedPrompt = ""
    @State private var responseText: String?
    @State private var isResponding = false
    @State private var promptTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    // Four destinations share the pill with the free-standing plus, so the
    // per-icon minimum has to leave the row room on a narrow phone; the
    // `maxWidth: .infinity` below spreads them out again wherever there is
    // space.
    private static let iconSize: CGFloat = 44
    private static let barHeight: CGFloat = 52

    /// Total height the dock occupies, its own vertical padding included.
    /// The shell hangs the dock off the root as a bottom safe-area inset, but
    /// that inset does not reach screens nested in their own navigation stack.
    static let occupiedHeight: CGFloat = barHeight + 12
    private static let morph = Animation.spring(response: 0.5, dampingFraction: 0.78)

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            if isInputExpanded {
                aiPromptInput
                    .matchedGeometryEffect(
                        id: "coveAIPrompt",
                        in: dockMorph,
                        properties: .frame,
                        anchor: .center,
                        isSource: false
                    )
                    .transition(
                        .scale(scale: 0.12, anchor: inputOriginAnchor)
                            .combined(with: .opacity)
                    )
            } else {
                HStack(spacing: 10) {
                    tabPill
                    addButton
                        .transition(.scale(scale: 0.55).combined(with: .opacity))
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .animation(reduceMotion ? nil : Self.morph, value: isInputExpanded)
    }

    private var tabPill: some View {
        HStack(spacing: 2) {
            ForEach(CoveTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity)
        .frame(height: Self.barHeight)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private func select(_ tab: CoveTab) {
        CoveHaptics.selection()
        guard selection != tab else { return }
        if reduceMotion {
            selection = tab
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                selection = tab
            }
        }
    }

    private func tabButton(for tab: CoveTab) -> some View {
        let isSelected = selection == tab

        return Image(systemName: isSelected ? tab.selectedSystemImage : tab.systemImage)
            .font(.system(size: 18, weight: .semibold))
            .contentTransition(.symbolEffect(.replace))
            .foregroundStyle(isSelected ? CoveTheme.ink : CoveTheme.ink.opacity(0.42))
            .frame(minWidth: Self.iconSize, maxWidth: .infinity)
            .frame(height: Self.barHeight - 8)
            .background {
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(CoveTheme.ink.opacity(0.10))
                            .matchedGeometryEffect(id: "coveTabIndicator", in: indicator)
                    }

                    // This almost-invisible capsule becomes the origin for the
                    // AI field. Its frame is the held tab, so the glass grows
                    // out of the finger's actual location instead of blooming
                    // from the center of the whole dock.
                    if inputSourceTab == tab, !isInputExpanded {
                        Capsule()
                            .fill(CoveTheme.ink.opacity(0.001))
                            .matchedGeometryEffect(
                                id: "coveAIPrompt",
                                in: dockMorph,
                                properties: .frame,
                                anchor: .center,
                                isSource: true
                            )
                    }
                }
            }
            .contentShape(Capsule())
            // One exclusive gesture resolves both interactions. Releasing
            // before the threshold is a tap; holding still past it opens the
            // field immediately. There is no drag or swipe phase.
            .gesture(
                LongPressGesture(minimumDuration: 0.42, maximumDistance: 18)
                    .exclusively(before: TapGesture())
                    .onEnded { result in
                        switch result {
                        case .first:
                            expandInput(from: tab)
                        case .second:
                            guard !isInputExpanded else { return }
                            select(tab)
                        }
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(tab.title)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
            .accessibilityAction { select(tab) }
            .accessibilityAction(named: "Ask Cove") {
                expandInput(from: tab)
            }
    }

    private var aiPromptInput: some View {
        Group {
            if isResponding || responseText != nil {
                aiPromptResult
            } else {
                aiPromptComposer
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isResponding || responseText != nil ? 132 : Self.barHeight)
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .animation(reduceMotion ? nil : Self.morph, value: isResponding)
        .animation(reduceMotion ? nil : Self.morph, value: responseText)
    }

    private var aiPromptComposer: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CoveTheme.ink.opacity(0.66))

            TextField("Ask Cove anything…", text: $promptText)
                .font(.subheadline)
                .foregroundStyle(CoveTheme.ink)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit(submitPrompt)

            if !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: submitPrompt) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CoveTheme.background)
                        .frame(width: 30, height: 30)
                        .background(CoveTheme.ink, in: Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Send to Cove")
            }

            Button(action: collapseInput) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CoveTheme.ink.opacity(0.64))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close AI prompt")
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: Self.barHeight)
    }

    private var aiPromptResult: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CoveTheme.ink.opacity(0.66))

                Text(submittedPrompt)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CoveTheme.ink.opacity(0.62))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Button(action: collapseInput) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CoveTheme.ink.opacity(0.64))
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close AI response")
            }

            if isResponding {
                // The same band the Home title sweeps while the shelf
                // reindexes, in place of a spinner: one "Cove is working"
                // signal, wherever the work is.
                Text("Thinking…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CoveTheme.ink.opacity(0.58))
                    .coveShimmer(isActive: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityLabel("Thinking")
            } else {
                ScrollView {
                    Text(responseText ?? "")
                        .font(.subheadline)
                        .foregroundStyle(CoveTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// The transition's fallback anchor also follows the held item. The
    /// matched-geometry source above is the primary motion; this keeps the
    /// origin correct when Reduce Motion or a mid-transition layout update
    /// prevents SwiftUI from pairing the two frames.
    private var inputOriginAnchor: UnitPoint {
        guard let inputSourceTab,
              let index = CoveTab.allCases.firstIndex(of: inputSourceTab) else {
            return .center
        }
        let tabFraction = (CGFloat(index) + 0.5) / CGFloat(CoveTab.allCases.count)
        // The tab pill occupies roughly the leading 82% of the complete dock;
        // the remaining space belongs to the separate add button.
        return UnitPoint(x: tabFraction * 0.82, y: 0.5)
    }

    private func expandInput(from tab: CoveTab) {
        guard !isInputExpanded else { return }
        CoveHaptics.impact(.medium)
        promptTask?.cancel()
        submittedPrompt = ""
        responseText = nil
        isResponding = false
        inputSourceTab = tab

        Task { @MainActor in
            // Give the origin capsule one layout pass before inserting the
            // destination. That makes the matched animation reliably begin at
            // the held item, even on the first interaction after launch.
            await Task.yield()
            withAnimation(reduceMotion ? nil : Self.morph) {
                isInputExpanded = true
            }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 150))
            guard isInputExpanded else { return }
            isInputFocused = true
        }
    }

    private func collapseInput() {
        CoveHaptics.selection()
        promptTask?.cancel()
        promptTask = nil
        isInputFocused = false
        withAnimation(reduceMotion ? nil : Self.morph) {
            isInputExpanded = false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 520))
            guard !isInputExpanded else { return }
            inputSourceTab = nil
            submittedPrompt = ""
            responseText = nil
            isResponding = false
        }
    }

    private func submitPrompt() {
        let prompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding else { return }
        CoveHaptics.impact(.light)
        isInputFocused = false
        submittedPrompt = prompt
        promptText = ""
        withAnimation(reduceMotion ? nil : Self.morph) {
            isResponding = true
        }

        promptTask = Task { @MainActor in
            let answer = await onAIPrompt(prompt)
            guard !Task.isCancelled, isInputExpanded else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
                responseText = answer
                isResponding = false
            }
            promptTask = nil
        }
    }

    private var addButton: some View {
        Menu {
            if CameraCaptureView.isAvailable {
                Button {
                    CoveHaptics.impact(.medium)
                    onCamera()
                } label: {
                    Label("Camera", systemImage: "camera")
                }
            }
            ForEach(AddCaptureMode.allCases) { mode in
                Button {
                    CoveHaptics.impact(.medium)
                    onAdd(mode)
                } label: {
                    Label(mode.rawValue, systemImage: mode.systemImage)
                }
            }
        } label: {
            // Solid ink, matched to the pill's height so the two read as one
            // dock: the filled circle is what separates the action from the
            // destinations beside it.
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(CoveTheme.background)
                .frame(width: Self.barHeight, height: Self.barHeight)
                .background(CoveTheme.ink, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add")
        .accessibilityHint("Add a screenshot, link, or note")
    }
}

#Preview("Tab bar") {
    @Previewable @State var selection: CoveTab = .home

    ZStack {
        CoveInkBackground()
        VStack {
            Spacer()
            CoveTabBar(selection: $selection)
        }
    }
}
