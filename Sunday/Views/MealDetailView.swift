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
        .toolbar { if !meal.isGone { toolbarContent } }
        .sheet(isPresented: $isEditing) {
            MealEditorView(meal: meal)
        }
        .confirmationDialog("Delete this dinner for everyone in the family?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete dinner", role: .destructive) {
                dismiss()
                store.delete(meal)
            }
        }
        .onAppear { stars = store.stars(for: meal) }
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
                        HStack(spacing: 8) { metaItems }
                        VStack(alignment: .leading, spacing: 6) { metaItems }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    let tags = FoodTags.decode(meal.tags)
                    if !tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(tags, id: \.self) { tag in
                                Text(FoodTags.displayName(tag))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1))
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Tags: \(tags.map(FoodTags.displayName).joined(separator: ", "))")
                    }
                }
                .padding(.horizontal)

                if let notes = meal.notes, !notes.isEmpty {
                    notesCard(notes)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your stars")
                        .font(.headline)
                    StarRatingView(stars: $stars, size: 28)
                    Label("Only you see your stars. Not even the cook.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

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
    private var metaItems: some View {
        Text((meal.date ?? .now).dinnerFormatted)
        if let cook = meal.cook, !cook.isEmpty {
            Text("·").accessibilityHidden(true)
            CookLabel(name: cook, size: 20)
        }
        Text("·").accessibilityHidden(true)
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
                    Text(summary.date.dinnerFormatted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Season.of(summary.date, hemisphere: .current).emoji)
                        .accessibilityHidden(true)
                    if isThis {
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
            .padding(.bottom, isLast ? 0 : 14)
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
            HStack(spacing: 6) {
                Text("\(dish.timesEaten) dinners since \(dish.meals.last?.date.formatted(.dateTime.month(.abbreviated).year()) ?? "")")
                if let average = dish.averageStars {
                    Text("·").accessibilityHidden(true)
                    Text("your average")
                    CompactStars(stars: average)
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
