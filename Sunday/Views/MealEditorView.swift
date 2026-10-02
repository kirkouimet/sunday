import CoreData
import PhotosUI
import SundayKit
import SwiftUI

/// Add a new dinner, or edit one (pass `meal`). Built to take seconds:
/// snap or pick photos, type a name, tap stars, save.
struct MealEditorView: View {
    var meal: Meal?

    @EnvironmentObject private var store: MealStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lastCook") private var lastCook = ""

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Meal.date, ascending: false)])
    private var allMeals: FetchedResults<Meal>

    @State private var draft = MealDraft()
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isShowingCamera = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didLoad = false
    @FocusState private var nameFocused: Bool

    private var isEditing: Bool { meal != nil }

    private var nameSuggestions: [String] {
        guard nameFocused else { return [] }
        let summaries = allMeals.compactMap { m -> MealSummary? in
            guard let id = m.id, let date = m.date else { return nil }
            return MealSummary(id: id, name: m.displayName, date: date, stars: nil)
        }
        return Suggestions(meals: summaries).nameSuggestions(for: draft.name)
    }

    private var previousTimes: Dish? {
        let summaries = allMeals.compactMap { m -> MealSummary? in
            guard m.objectID != meal?.objectID, let id = m.id, let date = m.date else { return nil }
            return MealSummary(id: id, name: m.displayName, date: date, stars: nil)
        }
        return Suggestions(meals: summaries).dish(named: draft.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                photosSection

                Section {
                    TextField("What's for dinner?", text: $draft.name)
                        .font(.title3)
                        .focused($nameFocused)
                        .submitLabel(.done)
                    if !nameSuggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(nameSuggestions, id: \.self) { name in
                                    Button(name) {
                                        draft.name = name
                                        nameFocused = false
                                    }
                                    .buttonStyle(.bordered)
                                    .font(.footnote)
                                }
                            }
                        }
                    }
                    if let previous = previousTimes {
                        Label("Had \(previous.timesEaten) time\(previous.timesEaten == 1 ? "" : "s") before · last on \(previous.lastEaten.dinnerFormatted)",
                              systemImage: "clock.arrow.circlepath")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    DatePicker("When", selection: $draft.date, displayedComponents: [.date])
                    TextField("Cooked by", text: $draft.cook)
                        .textContentType(.name)
                }

                Section {
                    HStack {
                        Spacer()
                        StarRatingView(stars: $draft.stars, size: 34)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Your stars")
                } footer: {
                    Text("Only you can see your rating.")
                }

                Section("Notes") {
                    TextField("What would you change next time?", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(isEditing ? "Edit dinner" : "New dinner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }
                            .bold()
                            .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty && draft.photos.isEmpty)
                    }
                }
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker { image in
                    draft.photos.append(.init(image: image))
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItems) { _, items in
                Task { await loadPicked(items) }
            }
            .alert("Couldn't save", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear(perform: loadDraft)
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var photosSection: some View {
        Section {
            if !draft.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(draft.photos) { photo in
                            Image(uiImage: photo.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 110, height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        draft.photos.removeAll { $0.id == photo.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                            .font(.title3)
                                    }
                                    .padding(4)
                                    .accessibilityLabel("Remove photo")
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack {
                if CameraPicker.isAvailable {
                    Button {
                        isShowingCamera = true
                    } label: {
                        Label("Take photo", systemImage: "camera.fill")
                    }
                    Spacer()
                }
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                    Label("Choose photos", systemImage: "photo.on.rectangle")
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private func loadDraft() {
        guard !didLoad else { return }
        didLoad = true
        if let meal {
            draft = MealDraft(meal: meal, stars: store.stars(for: meal))
        } else {
            draft.cook = lastCook
            if CameraPicker.isAvailable { isShowingCamera = true }
        }
    }

    private func loadPicked(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                draft.photos.append(.init(image: image))
            }
        }
        pickerItems = []
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await store.save(draft, editing: meal)
                if !draft.cook.isEmpty { lastCook = draft.cook }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

#Preview {
    MealEditorView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(MealStore(persistence: .preview))
}
