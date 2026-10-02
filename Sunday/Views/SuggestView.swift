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
    @State private var path: [NSManagedObjectID] = []
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var suggestions: Suggestions {
        Suggestions(meals: store.summaries(meals: Array(meals), ratings: Array(ratings)), hemisphere: .current)
    }

    var body: some View {
        NavigationStack(path: $path) {
            let suggestions = suggestions
            // Longest-missed first: that's the useful order when everything is a favorite.
            let favorites = Array(suggestions.favoritesDue()
                .sorted { $0.daysSinceLastEaten(now: .now) > $1.daysSinceLastEaten(now: .now) }
                .prefix(8))
            let seasonal = Array(suggestions.goodForThisSeason().prefix(8))
            let season = Season.of(.now, hemisphere: .current)
            let holiday = suggestions.upcomingHoliday()

            List {
                if !suggestions.dishes.isEmpty {
                    Section {
                        SurpriseCard(pick: surprise ?? suggestions.surprise(), store: store,
                                     onOpen: { path.append($0) }) {
                            withAnimation(reduceMotion ? nil : .spring(duration: 0.45)) {
                                surprise = suggestions.surprise()
                            }
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                if let holiday {
                    Section {
                        ForEach(holiday.meals.prefix(6)) { summary in
                            mealRow(summary)
                        }
                    } header: {
                        Text("\(holiday.holiday.emoji) \(holiday.holiday.name) is coming. Here's what we made before")
                    }
                }

                if !favorites.isEmpty {
                    Section {
                        ForEach(favorites) { dish in
                            dishRow(dish, detail: "Last had \(SundayCalendar.timeAgo(days: dish.daysSinceLastEaten(now: .now)).lowercased())")
                        }
                    } header: {
                        Text("Favorites we haven't had in a while")
                    }
                }

                if !seasonal.isEmpty {
                    Section {
                        ForEach(seasonal) { dish in
                            dishRow(dish, detail: "Last had \(SundayCalendar.timeAgo(days: dish.daysSinceLastEaten(now: .now)).lowercased())")
                        }
                    } header: {
                        Text("\(season.emoji) \(season.displayName) favorites")
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
            .navigationTitle(typeSize.isAccessibilitySize ? "Ideas" : "What's for dinner?")
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
                SuggestionRow(meal: meal, title: dish.displayName, detail: detail,
                              badge: dish.timesEaten > 1 ? "had \(dish.timesEaten)×" : nil)
            }
        }
    }

    @ViewBuilder
    private func mealRow(_ summary: MealSummary) -> some View {
        if let meal = store.meal(withID: summary.id) {
            NavigationLink(value: meal.objectID) {
                SuggestionRow(meal: meal, title: summary.name, detail: summary.date.dinnerFormatted, badge: nil)
            }
        }
    }
}

private struct SuggestionRow: View {
    @ObservedObject var meal: Meal
    let title: String
    let detail: String
    let badge: String?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            // Stack everything so long names and big text have the full width.
            VStack(alignment: .leading, spacing: 6) {
                thumbnail
                Text(title).font(.body.weight(.medium)).keepsake().lineLimit(3)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                if let badge { badgeView(badge) }
            }
            .padding(.vertical, 4)
        } else {
            HStack(spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.medium)).keepsake().lineLimit(2)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let badge { badgeView(badge) }
            }
        }
    }

    private func badgeView(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private var thumbnail: some View {
        PhotoThumbnail(photo: meal.sortedPhotos.first)
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// "Tonight, how about…" A big photo of one pick, a shuffle, and a way in.
private struct SurpriseCard: View {
    let pick: Dish?
    let store: MealStore
    var onOpen: (NSManagedObjectID) -> Void
    var onShuffle: () -> Void

    @State private var spins = 0

    var body: some View {
        let meal = pick.flatMap { store.meal(withID: $0.latestMealID) }
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                PhotoThumbnail(photo: meal?.sortedPhotos.first)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .id(pick?.key)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tonight, how about")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(pick?.displayName ?? "")
                        .font(.title.bold())
                        .keepsake()
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .contentTransition(.opacity)
                    if let pick {
                        Text("Last had \(SundayCalendar.timeAgo(days: pick.daysSinceLastEaten(now: .now)).lowercased())")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(16)
            }
            .clipped()

            HStack(spacing: 10) {
                if let meal {
                    // A Button, not a NavigationLink: inside a List a link
                    // turns into a plain row with a chevron.
                    Button {
                        onOpen(meal.objectID)
                    } label: {
                        Text("Let's make it").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button {
                    spins += 1
                    onShuffle()
                } label: {
                    Label("Another", systemImage: "dice.fill")
                        .symbolEffect(.bounce, value: spins)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .sensoryFeedback(.selection, trigger: spins)
        .accessibilityElement(children: .contain)
    }
}
