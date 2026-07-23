import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AddItemView: View {
    private enum CaptureMode: String, CaseIterable, Identifiable {
        case photo = "Photo"
        case link = "Link"
        case note = "Note"

        var id: String { rawValue }
    }

    @Environment(\.aiServices) private var aiServices
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var mode: CaptureMode = .photo
    @State private var imageKind: ShelfItemKind = .screenshot
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var title = ""
    @State private var userNote = ""
    @State private var linkText = ""
    @State private var noteText = ""
    @State private var photoLoadError: String?
    @State private var didSubmit = false

    var onDismiss: (Bool) -> Void = { _ in }

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
                    Button("Add", action: addItem)
                        .disabled(!canAdd)
                }
            }
            .alert("Couldn’t load that photo", isPresented: photoErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(photoLoadError ?? "Please choose another image.")
            }
            .onChange(of: selectedPhoto) { _, newPhoto in
                guard let newPhoto else {
                    selectedImageData = nil
                    return
                }

                Task {
                    do {
                        selectedImageData = try await newPhoto.loadTransferable(type: Data.self)
                        if selectedImageData == nil {
                            photoLoadError = "The selected asset didn’t provide image data."
                        }
                    } catch {
                        selectedImageData = nil
                        photoLoadError = error.localizedDescription
                    }
                }
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
            Section("Screenshot or image") {
                Picker("Kind", selection: $imageKind) {
                    Text("Screenshot").tag(ShelfItemKind.screenshot)
                    Text("Image").tag(ShelfItemKind.image)
                }
                .pickerStyle(.segmented)

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(
                        selectedImageData == nil ? "Choose from Photos" : "Choose a different photo",
                        systemImage: "photo.on.rectangle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)

                if let selectedImageData, let image = UIImage(data: selectedImageData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 240)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 18))
                        .accessibilityLabel("Selected image preview")
                }
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

    private var canAdd: Bool {
        switch mode {
        case .photo: selectedImageData != nil
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
        let item: ShelfItem
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = userNote.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .photo:
            item = ShelfItem(
                kind: imageKind,
                title: trimmedTitle.isEmpty ? "Saved \(imageKind.label.lowercased())" : trimmedTitle,
                userNote: trimmedNote.nilIfEmpty,
                imageData: selectedImageData,
                processingState: .queued
            )

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

        modelContext.insert(item)
        try? modelContext.save()

        let itemID = item.id
        Task {
            await ShelfProcessor.shared.enqueue(itemID: itemID)
        }
        didSubmit = true
        dismiss()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
