import CoreData
import SundayKit
import SwiftUI

/// "What should we eat?" answered from the family's own history.
struct SuggestView: View {
    @EnvironmentObject private var store: MealStore

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Meal.date, ascending: false)])
    private var meals: FetchedResults<Meal>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Rating.updatedAt, ascending: false)])
    private var ratings: FetchedResults<Rating>

    @State private var surprise: Dish?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var suggestions: Suggestions {
        Suggestions(meals: store.summaries(meals: Array(meals), ratings: Array(ratings)), hemisphere: .current)
    }

    var body: some View {
        NavigationStack {
            let suggestions = suggestions
            let favorites = Array(suggestions.favoritesDue().prefix(8))
            let pastYears = Array(suggestions.thisTimeInPastYears().prefix(8))
            let seasonal = Array(suggestions.goodForThisSeason().prefix(8))
            let season = Season.of(.now, hemisphere: .current)

            List {
                Section {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring) { surprise = suggestions.surprise() }
                    } label: {
                        HStack {
                            Image(systemName: "dice.fill")
                                .font(.title2)
                            VStack(alignment: .leading) {
                                Text("Surprise me").font(.headline)
                                Text("Pick one of our favorites").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(suggestions.dishes.isEmpty)

                    if let surprise {
                        dishRow(surprise, detail: "Last had \(surprise.lastEaten.dinnerFormatted)")
                    }
                }

                if !favorites.isEmpty {
                    Section {
                        ForEach(favorites) { dish in
                            dishRow(dish, detail: "\(dish.daysSinceLastEaten(now: .now)) days since we had it")
                        }
                    } header: {
                        Text("Favorites we haven't had in a while")
                    }
                }

                if !pastYears.isEmpty {
                    Section {
                        ForEach(pastYears) { summary in
                            mealRow(summary)
                        }
                    } header: {
                        Text("This time in past years")
                    }
                }

                if !seasonal.isEmpty {
                    Section {
                        ForEach(seasonal) { dish in
                            dishRow(dish, detail: "Had \(dish.timesEaten) time\(dish.timesEaten == 1 ? "" : "s")")
                        }
                    } header: {
                        Text("\(season.emoji) Good for \(season.displayName.lowercased())")
                    }
                }
            }
            .overlay {
                if suggestions.dishes.isEmpty {
                    ContentUnavailableView(
                        "Ideas will show up here",
                        systemImage: "sparkles",
                        description: Text("Log a few Sunday dinners and rate them. Sunday will start suggesting favorites, seasonal picks and what you ate this time last year.")
                    )
                }
            }
            .navigationTitle("What's for dinner?")
            .navigationDestination(for: NSManagedObjectID.self) { id in
                if let meal = try? store.context.existingObject(with: id) as? Meal {
                    MealDetailView(meal: meal)
                }
            }
        }
    }

    @ViewBuilder
    private func dishRow(_ dish: Dish, detail: String) -> some View {
        if let meal = store.meal(withID: dish.latestMealID) {
            NavigationLink(value: meal.objectID) {
                SuggestionRow(meal: meal, title: dish.displayName, detail: detail, stars: dish.averageStars)
            }
        }
    }

    @ViewBuilder
    private func mealRow(_ summary: MealSummary) -> some View {
        if let meal = store.meal(withID: summary.id) {
            NavigationLink(value: meal.objectID) {
                SuggestionRow(meal: meal, title: summary.name, detail: summary.date.dinnerFormatted, stars: summary.stars.map { Double($0) })
            }
        }
    }
}

private struct SuggestionRow: View {
    @ObservedObject var meal: Meal
    let title: String
    let detail: String
    let stars: Double?

    var body: some View {
        HStack(spacing: 12) {
            PhotoThumbnail(photo: meal.sortedPhotos.first)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium)).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let stars {
                YourStarsLabel(stars: stars, size: 10)
            }
        }
    }
}
