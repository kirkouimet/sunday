import CoreData
import ImageIO
import PhotosUI
import SundayKit
import SwiftUI

/// Add a new dinner, or edit one (pass `meal`). Built to take seconds:
/// snap a photo, type a name, hit Return.
struct MealEditorView: View {
    var meal: Meal?

    @EnvironmentObject private var store: MealStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lastCook") private var lastCook = ""

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Meal.date, ascending: false)])
    private var allMeals: FetchedResults<Meal>

    @State private var draft = MealDraft()
    @State private var initialFingerprint = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isShowingCamera = false
    @State private var isSaving = false
    @State private var isConfirmingDiscard = false
    @State private var errorMessage: String?
    @State private var didLoad = false
    @State private var didPickDateFromPhoto = false
    /// Set when you choose to add your photos to a dinner someone else
    /// already posted for the same day, instead of creating a duplicate.
    @State private var joinedMeal: Meal?
    @State private var dismissedSameDayPrompt = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, cook, notes }

    private var isEditing: Bool { meal != nil }
    /// The dinner being saved into: the one passed in, or one we joined.
    private var targetMeal: Meal? { meal ?? joinedMeal }

    /// A dinner already logged for the draft's day that you could join.
    private var sameDayMeal: Meal? {
        guard !isEditing, joinedMeal == nil, !dismissedSameDayPrompt else { return nil }
        return allMeals.first { other in
            guard let date = other.date, !other.isGone else { return false }
            return Calendar.current.isDate(date, inSameDayAs: draft.date) && store.canEdit(other)
        }
    }
    private var hasChanges: Bool { draft.fingerprint != initialFingerprint }
    private var canSave: Bool {
        !isSaving && (!draft.name.trimmingCharacters(in: .whitespaces).isEmpty || !draft.photos.isEmpty)
    }

    private var otherMeals: [MealSummary] {
        allMeals.compactMap { m -> MealSummary? in
            guard m.objectID != targetMeal?.objectID, let id = m.id, let date = m.date else { return nil }
            return MealSummary(id: id, name: m.displayName, date: date, stars: nil)
        }
    }

    private var nameSuggestions: [String] {
        guard focusedField == .name else { return [] }
        return Suggestions(meals: otherMeals).nameSuggestions(for: draft.name)
    }

    private var previousTimes: Dish? {
        Suggestions(meals: otherMeals).dish(named: draft.name)
    }

    private var pastCooks: [String] {
        var seen = Set<String>()
        return allMeals.compactMap { $0.cook?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .filter { $0.caseInsensitiveCompare(draft.cook) != .orderedSame }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let sameDayMeal {
                    sameDayPrompt(sameDayMeal)
                }
                if let joinedMeal {
                    Section {
                        Label("Adding your photos and stars to \(joinedMeal.displayName)", systemImage: "person.2.fill")
                            .font(.subheadline)
                    }
                }
                photosSection
                dinnerSection
                starsSection
            }
            .navigationTitle(isEditing ? "Edit dinner" : joinedMeal != nil ? "Add to dinner" : "New dinner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { isConfirmingDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .bold()
                            .disabled(!canSave)
                    }
                }
            }
            .confirmationDialog(isEditing ? "Discard your changes?" : "Discard this dinner?",
                                isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                CameraPicker { image in
                    draft.photos.append(.init(image: image))
                }
                .ignoresSafeArea()
            }
            .onChange(of: isShowingCamera) { _, showing in
                if !showing, draft.name.isEmpty { focusedField = .name }
            }
            .onChange(of: pickerItems) { _, items in
                Task { await loadPicked(items) }
            }
            .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear(perform: loadDraft)
            .interactiveDismissDisabled(isSaving || hasChanges)
        }
    }

    // MARK: Sections

    private var photosSection: some View {
        Section {
            if !draft.photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(draft.photos.enumerated()), id: \.element.id) { index, photo in
                            Image(uiImage: photo.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 110, height: 110)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .accessibilityLabel("Photo \(index + 1) of \(draft.photos.count)")
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        withAnimation { draft.photos.removeAll { $0.id == photo.id } }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                            .font(.title3)
                                            .frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Remove photo \(index + 1)")
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

    private var dinnerSection: some View {
        Section {
            TextField("Name this dinner", text: $draft.name)
                .font(.title3)
                .focused($focusedField, equals: .name)
                .submitLabel(.done)
                .onSubmit { if canSave { save() } }

            if !nameSuggestions.isEmpty {
                chipRow(nameSuggestions) { name in
                    draft.name = name
                    focusedField = nil
                }
            }

            dishHistoryLine

            DatePicker("When", selection: $draft.date, in: ...Date.now.addingTimeInterval(86_400), displayedComponents: [.date])

            TextField("Cooked by", text: $draft.cook)
                .focused($focusedField, equals: .cook)
                .textInputAutocapitalization(.words)
            if !pastCooks.isEmpty, focusedField == .cook || draft.cook.isEmpty {
                chipRow(pastCooks) { cook in
                    draft.cook = cook
                    focusedField = nil
                }
            }

            TextField("Who was there? Anything to remember?", text: $draft.notes, axis: .vertical)
                .focused($focusedField, equals: .notes)
                .lineLimit(2...6)
        } footer: {
            Text("Everyone in the family sees the photos, name and notes.")
        }
    }

    @ViewBuilder
    private var dishHistoryLine: some View {
        let trimmed = draft.name.trimmingCharacters(in: .whitespaces)
        if let previous = previousTimes {
            Label(previous.timesEaten == 1
                  ? "We've had this once before, on \(previous.lastEaten.dinnerFormatted)"
                  : "We've had this \(previous.timesEaten) times, last on \(previous.lastEaten.dinnerFormatted)",
                  systemImage: "clock.arrow.circlepath")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if !trimmed.isEmpty, !isEditing, joinedMeal == nil, nameSuggestions.isEmpty, focusedField != .name {
            Label("A new one for the family!", systemImage: "sparkle")
                .font(.footnote)
                .foregroundStyle(Color.sundayAccent)
        }
    }

    private var starsSection: some View {
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
            Label("Only you see your stars. Not even the cook.", systemImage: "lock.fill")
        }
    }

    private func sameDayPrompt(_ other: Meal) -> some View {
        Section {
            HStack(spacing: 12) {
                PhotoThumbnail(photo: other.sortedPhotos.first)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Calendar.current.isDateInToday(other.date ?? .distantPast)
                         ? "Tonight's dinner is already posted" : "A dinner is already posted for this day")
                        .font(.subheadline.weight(.semibold))
                    Text(other.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Button {
                join(other)
            } label: {
                Label("Add my photos to it", systemImage: "photo.badge.plus")
            }
            Button("This is a different dinner") {
                withAnimation { dismissedSameDayPrompt = true }
            }
            .foregroundStyle(.secondary)
        }
    }

    /// Switch from "new dinner" to adding into an existing one: keep its
    /// details and photos, append the photos you've picked so far.
    private func join(_ other: Meal) {
        var merged = MealDraft(meal: other, stars: store.stars(for: other))
        merged.photos.append(contentsOf: draft.photos.filter { $0.existing == nil })
        if merged.stars == 0 { merged.stars = draft.stars }
        withAnimation {
            joinedMeal = other
            draft = merged
        }
        focusedField = nil
    }

    private func chipRow(_ items: [String], action: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(items, id: \.self) { item in
                    Button(item) { action(item) }
                        .buttonStyle(.bordered)
                        .font(.footnote)
                }
            }
        }
    }

    // MARK: Actions

    private func loadDraft() {
        guard !didLoad else { return }
        didLoad = true
        if let meal {
            draft = MealDraft(meal: meal, stars: store.stars(for: meal))
        } else {
            draft.cook = lastCook
            draft.date = SundayCalendar.mostRecentSunday(onOrBefore: .now)
            // On Sunday you're at the table: go straight to the camera.
            // Any other day you're probably catching up from the camera roll.
            if CameraPicker.isAvailable, SundayCalendar.isSunday(.now) {
                // Let the sheet finish presenting before covering it.
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    isShowingCamera = true
                }
            } else {
                focusedField = .name
            }
        }
        initialFingerprint = draft.fingerprint
    }

    private func loadPicked(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { continue }
            if !isEditing, !didPickDateFromPhoto, let taken = Self.captureDate(of: data) {
                draft.date = taken
                didPickDateFromPhoto = true
            }
            draft.photos.append(.init(image: image))
        }
        pickerItems = []
        if draft.name.isEmpty { focusedField = .name }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        focusedField = nil
        Task {
            do {
                try await store.save(draft, editing: targetMeal)
                if !draft.cook.isEmpty { lastCook = draft.cook }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }

    /// When the photo was taken, from its EXIF data, so logging Monday from the
    /// camera roll still lands on Sunday.
    static func captureDate(of data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // EXIF times are local to where the photo was taken; use the recorded
        // offset when there is one (e.g. "-07:00"), else assume this device's zone.
        if let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
            if let date = formatter.date(from: raw + offset) { return date }
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: raw)
    }
}

#Preview {
    MealEditorView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(MealStore(persistence: .preview))
}
