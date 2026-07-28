import PhotosUI
import SwiftData
import SwiftUI
import UIKit

enum AddCaptureMode: String, CaseIterable, Identifiable {
    case photo = "Photo"
    case link = "Link"
    case note = "Note"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .photo: "photo.on.rectangle"
        case .link: "link"
        case .note: "note.text"
        }
    }
}

struct AddItemView: View {
    private typealias CaptureMode = AddCaptureMode

    @Environment(\.aiServices) private var aiServices
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var mode: CaptureMode
    @State private var imageKind: ShelfItemKind = .screenshot
    @State private var selectedPhotos: [PhotosPickerItem] = []
    /// Decoded in pick order, so the previews and the saved items match the
    /// order the picker numbered them in.
    @State private var selectedImages: [Data] = []
    @State private var isLoadingPhotos = false
    @State private var title = ""
    @State private var userNote = ""
    @State private var linkText = ""
    @State private var noteText = ""
    @State private var photoLoadError: String?
    @State private var didSubmit = false

    var onDismiss: (Bool) -> Void

    init(
        initialMode: AddCaptureMode = .photo,
        onDismiss: @escaping (Bool) -> Void = { _ in }
    ) {
        _mode = State(initialValue: initialMode)
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Capture type", selection: $mode) {
                    ForEach(CaptureMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                captureFields

                Section("Optional context") {
                    TextField("Title", text: $title)
                    if mode != .note {
                        TextField("Add a note", text: $userNote, axis: .vertical)
                            .lineLimit(2...5)
                    }
                }
            }
            .navigationTitle("Add to Cove")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(addButtonTitle, action: addItem)
                        .disabled(!canAdd)
                }
            }
            .alert("Couldn’t load that photo", isPresented: photoErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(photoLoadError ?? "Please choose another image.")
            }
            // `task(id:)` rather than `onChange`: reopening the picker while a
            // previous batch is still decoding cancels that load instead of
            // letting the two race to assign `selectedImages`.
            .task(id: selectedPhotos) {
                await loadSelectedPhotos()
            }
            .onChange(of: mode) { _, _ in
                title = ""
                userNote = ""
            }
            .onDisappear {
                onDismiss(didSubmit)
            }
        }
    }

    @ViewBuilder
    private var captureFields: some View {
        switch mode {
        case .photo:
            Section(selectedImages.count > 1 ? "Screenshots or images" : "Screenshot or image") {
                Picker("Kind", selection: $imageKind) {
                    Text("Screenshot").tag(ShelfItemKind.screenshot)
                    Text("Image").tag(ShelfItemKind.image)
                }
                .pickerStyle(.segmented)

                // `.ordered` numbers the selection as it's made, so the badges
                // in the picker match the order these get saved in.
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: nil,
                    selectionBehavior: .ordered,
                    matching: .images
                ) {
                    Label(photoPickerTitle, systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                photoPreview
            }

        case .link:
            Section("Link") {
                TextField("example.com/article", text: $linkText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                if !linkText.isEmpty, normalizedURL == nil {
                    Label("Enter a valid web address", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

        case .note:
            Section("Thought") {
                TextEditor(text: $noteText)
                    .frame(minHeight: 180)
                    .overlay(alignment: .topLeading) {
                        if noteText.isEmpty {
                            Text("Write something you want to find again…")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }

    // MARK: - Photos

    private var photoPickerTitle: String {
        switch selectedImages.count {
        case 0: "Choose from Photos"
        case 1: "Choose different photos"
        case let count: "\(count) photos selected · change"
        }
    }

    private var addButtonTitle: String {
        mode == .photo && selectedImages.count > 1 ? "Add \(selectedImages.count)" : "Add"
    }

    @ViewBuilder
    private var photoPreview: some View {
        if isLoadingPhotos {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Loading \(selectedPhotos.count) photo\(selectedPhotos.count == 1 ? "" : "s")…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if selectedImages.count == 1, let image = UIImage(data: selectedImages[0]) {
            // A single pick still gets the full-size preview it always had.
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 18))
                .accessibilityLabel("Selected image preview")
        } else if !selectedImages.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, data in
                        if let image = UIImage(data: data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 92, height: 92)
                                .clipShape(.rect(cornerRadius: 12))
                                .overlay(alignment: .topLeading) {
                                    Text("\(index + 1)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.black.opacity(0.45), in: Capsule())
                                        .padding(5)
                                }
                                .accessibilityLabel("Selected image \(index + 1) of \(selectedImages.count)")
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Decodes the picked assets in order. Partial failures keep whatever did
    /// load rather than throwing the whole batch away — one unreadable asset
    /// shouldn't cost the user the other nine.
    private func loadSelectedPhotos() async {
        guard !selectedPhotos.isEmpty else {
            selectedImages = []
            return
        }

        isLoadingPhotos = true
        defer { isLoadingPhotos = false }

        var loaded: [Data] = []
        var failures = 0

        for photo in selectedPhotos {
            guard !Task.isCancelled else { return }
            do {
                if let data = try await photo.loadTransferable(type: Data.self) {
                    loaded.append(data)
                } else {
                    failures += 1
                }
            } catch {
                failures += 1
            }
        }

        guard !Task.isCancelled else { return }
        selectedImages = loaded

        if failures > 0 {
            photoLoadError = loaded.isEmpty
                ? "None of the selected photos provided image data."
                : "\(failures) of \(selectedPhotos.count) photos couldn’t be read. The rest are ready to add."
        }
    }

    private var canAdd: Bool {
        switch mode {
        case .photo: !selectedImages.isEmpty && !isLoadingPhotos
        case .link: normalizedURL != nil
        case .note: !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var normalizedURL: URL? {
        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host() != nil else {
            return nil
        }
        return url
    }

    private var photoErrorBinding: Binding<Bool> {
        Binding(
            get: { photoLoadError != nil },
            set: { if !$0 { photoLoadError = nil } }
        )
    }

    private func addItem() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = userNote.trimmingCharacters(in: .whitespacesAndNewlines)

        // A photo capture can now produce several items, so the whole thing
        // works in batches — the other two modes just make a batch of one.
        let item: ShelfItem

        switch mode {
        case .photo:
            let base = trimmedTitle.isEmpty
                ? "Saved \(imageKind.label.lowercased())"
                : trimmedTitle
            let items = selectedImages.enumerated().map { index, data in
                ShelfItem(
                    kind: imageKind,
                    // Numbered only when there's more than one, so a single
                    // pick still reads as it always did.
                    title: selectedImages.count == 1 ? base : "\(base) \(index + 1)",
                    userNote: trimmedNote.nilIfEmpty,
                    imageData: data,
                    processingState: .queued
                )
            }
            guard !items.isEmpty else { return }
            save(items)
            return

        case .link:
            guard let url = normalizedURL else { return }
            let host = url.host() ?? "Saved link"
            let mockTitle = host.replacingOccurrences(of: "www.", with: "").capitalized
            item = ShelfItem(
                kind: .link,
                title: trimmedTitle.isEmpty ? mockTitle : trimmedTitle,
                userNote: trimmedNote.nilIfEmpty,
                linkURL: url,
                linkTitle: "\(mockTitle) · saved article",
                linkHost: host,
                processingState: .queued
            )

        case .note:
            let trimmedBody = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackTitle = trimmedBody.split(separator: "\n").first.map(String.init) ?? "Quick note"
            item = ShelfItem(
                kind: .text,
                title: trimmedTitle.isEmpty ? String(fallbackTitle.prefix(54)) : trimmedTitle,
                userNote: trimmedBody,
                processingState: .queued
            )
        }

        save([item])
    }

    /// Inserts a batch, saves once, and queues each for processing.
    private func save(_ items: [ShelfItem]) {
        for item in items {
            modelContext.insert(item)
        }
        try? modelContext.save()

        let ids = items.map(\.id)
        Task {
            for id in ids {
                await ShelfProcessor.shared.enqueue(itemID: id)
            }
        }
        didSubmit = true
        dismiss()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
