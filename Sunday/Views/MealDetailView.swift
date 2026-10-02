import CoreData
import SundayKit
import SwiftUI
import UniformTypeIdentifiers

struct MealDetailView: View {
    @ObservedObject var meal: Meal

    @EnvironmentObject private var store: MealStore
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Meal.date, ascending: false)])
    private var allMeals: FetchedResults<Meal>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Rating.updatedAt, ascending: false)])
    private var ratings: FetchedResults<Rating>

    @State private var stars = 0
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var isWritingRecipe = false
    @State private var recipeText = ""
    @State private var recipeAudio: Data?
    @State private var isRecipeExpanded = false
    @State private var hadStarsOnOpen = true
    /// Set when recording a guest's story instead of the dish's recipe.
    @State private var storyTeller: String?
    @State private var isTranscribing = false
    @State private var isChangingStars = false
    @StateObject private var voice = VoiceMemo()
    @Environment(\.dynamicTypeSize) private var typeSize

    private var dish: Dish? {
        Suggestions(meals: store.summaries(meals: Array(allMeals), ratings: Array(ratings)), hemisphere: .current)
            .dish(named: meal.displayName)
    }

    var body: some View {
        Group {
            if meal.isGone {
                ContentUnavailableView("This dinner was deleted", systemImage: "trash")
            } else {
                content
            }
        }
        // The big title on the page is the title; keep the bar clear so the
        // photo runs up under it.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .clearNavigationBarOnGlass()
        .toolbar(.hidden, for: .tabBar)
        .toolbar { if !meal.isGone { toolbarContent } }
        .sheet(isPresented: $isEditing) {
            MealEditorView(meal: meal)
        }
        .sheet(isPresented: $isWritingRecipe) {
            NavigationStack {
                VStack(spacing: 0) {
                    voiceRecorderRow
                        .padding()
                    Divider()
                TextEditor(text: $recipeText)
                    .font(.body)
                    .padding(.horizontal)
                    .overlay(alignment: .topLeading) {
                        if recipeText.isEmpty {
                            Text("Ingredients, then steps. However Grandma would say it.")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 22)
                                .padding(.top, 8)
                                .allowsHitTesting(false)
                        }
                    }
                }
                    .navigationTitle(storyTeller.map { "\($0)'s story" } ?? "How we make \(meal.displayName)")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isWritingRecipe = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                if voice.isRecording { voice.stopRecording() }
                                let audio = voice.recorded ?? recipeAudio
                                if let storyTeller {
                                    // A guest's story: its own place on this dinner. It can
                                    // never overwrite the dish's recipe.
                                    store.setStory(recipeText, audio: audio, by: storyTeller, for: meal)
                                } else {
                                    let target = recipeSource ?? meal
                                    store.setRecipe(recipeText, audio: audio, by: target.recipeBy ?? target.cook, for: target)
                                }
                                voice.discardRecording()
                                isWritingRecipe = false
                            }
                            .bold()
                        }
                    }
            }
        }
        .confirmationDialog("Delete this dinner for everyone in the family?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete dinner", role: .destructive) {
                dismiss()
                store.delete(meal)
            }
        }
        .onAppear {
            stars = store.stars(for: meal)
            hadStarsOnOpen = stars > 0
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { stars = store.stars(for: meal) }
        }
        .onChange(of: stars) { _, newValue in
            guard !meal.isGone, newValue != store.stars(for: meal) else { return }
            store.setRating(newValue, for: meal)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                photos

                VStack(alignment: .leading, spacing: 10) {
                    Text(meal.displayName)
                        .font(.largeTitle.bold())
                        .keepsake()
                        .accessibilityAddTraits(.isHeader)
                    // One line of facts: when · who · season or holiday.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { metaItems(separated: true) }
                        VStack(alignment: .leading, spacing: 6) { metaItems(separated: false) }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                // Unrated? Your stars come first, right under the facts.
                if !hadStarsOnOpen {
                    yourStars
                }

                if let notes = meal.notes, !notes.isEmpty {
                    notesCard(notes)
                }

                atTheTable

                storyCard

                recipeCard

                if hadStarsOnOpen {
                    yourStars
                }

                if let dish, dish.timesEaten > 1 {
                    history(dish)
                }
            }
            .padding(.bottom, 32)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(edges: .top)
    }

    @ViewBuilder
    private var yourStars: some View {
        if stars > 0, !isChangingStars {
            HStack(spacing: 8) {
                Text("Your stars").font(.subheadline).foregroundStyle(.secondary)
                CompactStars(stars: Double(stars))
                Spacer()
                Button("Change") { withAnimation { isChangingStars = true } }
                    .font(.subheadline)
            }
            .padding(.horizontal)
        } else {
            fullStars
        }
    }

    private var fullStars: some View {
        VStack(alignment: .leading, spacing: 8) {
                    Text("Your stars")
                        .font(.headline)
                    StarRatingView(stars: $stars, size: 28)
                    if stars > 0, let id = meal.id, let dish, let line = PersonalInsight.line(for: id, in: dish) {
                        Text(line)
                            .font(.callout)
                            .italic()
                            .keepsake()
                            .transition(.opacity)
                    }
                    Label("Only you see your stars. Not even the cook.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
    }

    /// Faces of who was there, and the moment it marks ("First Sunday with June").
    @ViewBuilder
    private var atTheTable: some View {
        let people = Attendance.decode(meal.attendees)
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("At the table")
                    .font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(people, id: \.self) { person in
                            NavigationLink(value: PersonRoute(name: person)) {
                                VStack(spacing: 4) {
                                    CookAvatar(name: person, size: 40)
                                    Text(person).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                                }
                                .frame(width: 72)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(person)
                        }
                    }
                }
                if let id = meal.id, let moment = Attendance.moment(for: id, in: allMeals.filter { !$0.isPlan }.compactMap { m -> Attendance.Dinner? in
                    guard let mid = m.id, let date = m.date else { return nil }
                    return Attendance.Dinner(id: mid, date: date, people: Attendance.decode(m.attendees))
                }) {
                    Label(moment, systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.sundayAccent)
                    if moment.hasPrefix("First Sunday with "), store.canEdit(meal) {
                        let guest = String(moment.dropFirst("First Sunday with ".count))
                        Button {
                            storyTeller = guest
                            recipeText = meal.storyBy == guest ? (meal.story ?? "") : ""
                            recipeAudio = meal.storyBy == guest ? meal.storyAudio : nil
                            isWritingRecipe = true
                        } label: {
                            Label(meal.storyBy == guest ? "Hear \(guest)'s story" : "Ask \(guest) to tell a recipe", systemImage: "mic")
                                .font(.subheadline)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .accessibilityElement(children: .contain)
        }
    }

    /// A guest's story from this dinner, in their voice.
    @ViewBuilder
    private var storyCard: some View {
        if let teller = meal.storyBy, meal.story != nil || meal.storyAudio != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    CookAvatar(name: teller, size: 28)
                    Text("\(teller)'s story")
                        .font(.title3.weight(.semibold))
                        .keepsake()
                }
                if let audio = meal.storyAudio {
                    Button {
                        voice.isPlaying ? voice.stop() : voice.play(audio)
                    } label: {
                        Label(voice.isPlaying ? "Stop" : "Hear \(teller) tell it",
                              systemImage: voice.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.bordered)
                }
                if let text = meal.story {
                    Text(text).italic().keepsake()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)
        }
    }

    /// The family's own way of making it: an heirloom, written once,
    /// shown on every time we've had this.
    @ViewBuilder
    private var recipeCard: some View {
        let familyRecipe = recipeSource
        if let familyRecipe, familyRecipe.recipe != nil || familyRecipe.recipeAudio != nil {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.snappy) { isRecipeExpanded.toggle() }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("How we make it")
                                .font(.title3.weight(.semibold))
                                .keepsake()
                            if let teller = familyRecipe.recipeBy ?? familyRecipe.cook, !teller.isEmpty {
                                Text("\(teller)'s way")
                                    .font(.subheadline)
                                    .italic()
                                    .keepsake()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(isRecipeExpanded ? 180 : 0))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(isRecipeExpanded ? "Collapses the recipe" : "Shows the recipe")

                if let audio = familyRecipe.recipeAudio {
                    Button {
                        voice.isPlaying ? voice.stop() : voice.play(audio)
                    } label: {
                        Label(voice.isPlaying ? "Stop" : "Hear \((familyRecipe.recipeBy ?? familyRecipe.cook).flatMap { $0.isEmpty ? nil : $0 } ?? "them") tell it",
                              systemImage: voice.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.bordered)
                }

                if isRecipeExpanded {
                    if let text = familyRecipe.recipe {
                        Text(text)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if store.canEdit(familyRecipe) {
                        Button("Edit recipe") {
                            storyTeller = nil
                            recipeText = familyRecipe.recipe ?? ""
                            recipeAudio = familyRecipe.recipeAudio
                            isWritingRecipe = true
                        }
                        .font(.subheadline)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal)
        } else if let dish, dish.timesEaten >= 2, store.canEdit(meal) {
            Button {
                storyTeller = nil
                recipeText = ""
                recipeAudio = nil
                isWritingRecipe = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("How do you make it?", systemImage: "book.closed")
                        .font(.headline)
                    Text("You've had this \(dish.timesEaten) times. Write it down once and it's here for good.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
    }

    /// "Tell it in your own words": a voice memo is the heirloom.
    private var voiceRecorderRow: some View {
        HStack(spacing: 12) {
            Button {
                if voice.isRecording {
                    voice.stopRecording()
                    // Voice → text, on the device, so it can be read and searched.
                    if recipeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let audio = voice.recorded {
                        isTranscribing = true
                        Task {
                            if let text = await Transcriber.transcribe(audio) { recipeText = text }
                            isTranscribing = false
                        }
                    }
                } else {
                    Task { await voice.startRecording() }
                }
            } label: {
                Label(voice.isRecording ? "Stop" : (voice.recorded ?? recipeAudio) == nil ? "Record it out loud" : "Record again",
                      systemImage: voice.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(voice.isRecording ? .red : Color.sundayAccent)
            if isTranscribing {
                ProgressView()
                Text("Writing it down…").font(.footnote).foregroundStyle(.secondary)
            } else if voice.isRecording {
                Text(Duration.seconds(voice.elapsed).formatted(.time(pattern: .minuteSecond)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else if let audio = voice.recorded ?? recipeAudio {
                Button {
                    voice.isPlaying ? voice.stop() : voice.play(audio)
                } label: {
                    Image(systemName: voice.isPlaying ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(voice.isPlaying ? "Stop" : "Play recording")
            }
            Spacer()
        }
    }

    /// The newest dinner of this dish that has a recipe written down.
    private var recipeSource: Meal? {
        let key = MealName.normalize(meal.displayName)
        func hasRecipe(_ m: Meal) -> Bool { m.recipe?.isEmpty == false || m.recipeAudio != nil }
        if hasRecipe(meal) { return meal }
        return allMeals.first { MealName.normalize($0.displayName) == key && hasRecipe($0) }
    }

    @ViewBuilder
    private func metaItems(separated: Bool) -> some View {
        Text((meal.date ?? .now).dinnerFormatted)
        if let cook = meal.cook, !cook.isEmpty {
            if separated { Text("·").accessibilityHidden(true) }
            CookLabel(name: cook, size: 20)
        }
        if separated { Text("·").accessibilityHidden(true) }
        if let holiday = meal.holiday {
            Text(holiday.label).accessibilityLabel(holiday.name)
        } else {
            Text("\(meal.season.emoji) \(meal.season.displayName)").accessibilityLabel(meal.season.displayName)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if let photo = meal.sortedPhotos.first, let data = photo.imageData ?? photo.thumbnailData {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: SharedPhoto(data: data),
                          preview: SharePreview(meal.displayName)) {
                    Label("Share photo", systemImage: "square.and.arrow.up")
                }
            }
        }
        if store.canEdit(meal) || store.canDelete(meal) {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if store.canEdit(meal) {
                        Button {
                            isEditing = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                    if store.canDelete(meal) {
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    @ViewBuilder
    private var photos: some View {
        let photos = meal.sortedPhotos
        if photos.isEmpty {
            PhotoThumbnail(photo: nil)
                .frame(height: 220)
                .accessibilityHidden(true)
        } else {
            TabView {
                ForEach(Array(photos.enumerated()), id: \.element.objectID) { index, photo in
                    PhotoThumbnail(photo: photo, useFullImage: true)
                        .accessibilityElement()
                        .accessibilityLabel("Photo \(index + 1) of \(photos.count) of \(meal.displayName)")
                        .accessibilityAddTraits(.isImage)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .frame(height: 420)
            .clipShape(RoundedRectangle(cornerRadius: 0))
        }
    }

    /// The emotional core of the page: set like a quote in a family album.
    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "quote.opening")
                .font(.title2)
                .foregroundStyle(Color.sundayAccent.opacity(0.7))
                .accessibilityHidden(true)
            Text(notes)
                .font(.title3)
                .italic()
                .keepsake()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Notes: \(notes)")
    }

    /// One stop on the dish's timeline; other dinners link to their page.
    @ViewBuilder
    private func timelineRow(_ summary: MealSummary, isLast: Bool) -> some View {
        let isThis = summary.id == meal.id
        let row = HStack(alignment: .top, spacing: 12) {
            // The column stretches to the row's height (fixedSize below), so
            // the line reaches down to the next dinner's dot.
            VStack(spacing: 0) {
                Circle()
                    .fill(isThis ? Color.sundayAccent : Color.secondary.opacity(0.5))
                    .frame(width: 10, height: 10)
                    .padding(.top, 11)
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 10)
            .frame(maxHeight: .infinity, alignment: .top)

            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(spacing: 8))
            if let other = store.meal(withID: summary.id) {
                PhotoThumbnail(photo: other.sortedPhotos.first)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
            }
            layout {
                HStack(spacing: 6) {
                    Text(summary.date.formatted(.dateTime.month(.abbreviated).day().year()))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Season.of(summary.date, hemisphere: .current).emoji)
                        .accessibilityHidden(true)
                    if isThis, !typeSize.isAccessibilitySize {
                        Text("This dinner")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.sundayAccent)
                    }
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                if let stars = summary.stars {
                    YourStarsLabel(stars: Double(stars), size: 11)
                }
            }
            .padding(.bottom, isLast ? 0 : 20)
        }
        .fixedSize(horizontal: false, vertical: true)
        .font(.subheadline)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)

        if !isThis, let other = store.meal(withID: summary.id) {
            NavigationLink(value: other.objectID) { row }
                .buttonStyle(.plain)
        } else {
            row.accessibilityAddTraits(.isSelected)
        }
    }

    private func history(_ dish: Dish) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Every time we've had this")
                .font(.title3.weight(.semibold))
                .keepsake()
                .accessibilityAddTraits(.isHeader)
            let subtitleLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 6))
            subtitleLayout {
                Text("\(dish.timesEaten) dinners since \(dish.meals.last?.date.formatted(.dateTime.month(.abbreviated).year()) ?? "")")
                if let average = dish.averageStars {
                    HStack(spacing: 4) {
                        Text("your average")
                        CompactStars(stars: average)
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(dish.meals.enumerated()), id: \.element.id) { index, summary in
                    timelineRow(summary, isLast: index == dish.meals.count - 1)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }
}

/// A photo's JPEG bytes, shared without decoding the image first.
struct SharedPhoto: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { $0.data }
    }
}

extension View {
    /// On iOS 26 the glass toolbar floats over the photo. Earlier versions
    /// keep the standard bar so text never scrolls under bare buttons.
    @ViewBuilder
    func clearNavigationBarOnGlass() -> some View {
        if #available(iOS 26.0, *) {
            self.toolbarBackground(.hidden, for: .navigationBar)
        } else {
            self
        }
    }
}
