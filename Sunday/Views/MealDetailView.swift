import CoreData
import SundayKit
import SwiftUI

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

    private var dish: Dish? {
        Suggestions(meals: store.summaries(meals: Array(allMeals), ratings: Array(ratings)), hemisphere: .current)
            .dish(named: meal.displayName)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                photos

                VStack(alignment: .leading, spacing: 8) {
                    Text(meal.displayName)
                        .font(.largeTitle.bold())
                    HStack(spacing: 8) {
                        Text((meal.date ?? .now).dinnerFormatted)
                        SeasonBadge(season: meal.season)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if let cook = meal.cook, !cook.isEmpty {
                        Label("Made by \(cook)", systemImage: "frying.pan")
                            .font(.subheadline)
                    }
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your stars")
                        .font(.headline)
                    StarRatingView(stars: $stars, size: 32)
                    Text("Private to you — nobody else in the family sees this.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                if let notes = meal.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes").font(.headline)
                        Text(notes)
                    }
                    .padding(.horizontal)
                }

                if let dish, dish.timesEaten > 1 {
                    history(dish)
                }
            }
            .padding(.bottom, 32)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.canEdit(meal) {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isEditing = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
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
            if newValue != store.stars(for: meal) { store.setRating(newValue, for: meal) }
        }
    }

    @ViewBuilder
    private var photos: some View {
        let photos = meal.sortedPhotos
        if photos.isEmpty {
            PhotoThumbnail(photo: nil)
                .frame(height: 220)
        } else {
            TabView {
                ForEach(photos) { photo in
                    PhotoThumbnail(photo: photo, useFullImage: true)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .frame(height: 380)
        }
    }

    private func history(_ dish: Dish) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Every time we've had this")
                    .font(.headline)
                Spacer()
                if let average = dish.averageStars {
                    StarsLabel(stars: average, size: 13)
                }
            }
            Text("\(dish.timesEaten) dinners · first on \(dish.meals.last?.date.dinnerFormatted ?? "")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(dish.meals) { summary in
                HStack {
                    Image(systemName: summary.id == meal.id ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(summary.id == meal.id ? Color.sundayAccent : Color.secondary)
                    Text(summary.date.dinnerFormatted)
                    Text(Season.of(summary.date, hemisphere: .current).emoji)
                    Spacer()
                    if let stars = summary.stars {
                        StarsLabel(stars: Double(stars), size: 11)
                    }
                }
                .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
    }
}
