import CoreData
import SundayKit
import SwiftUI

/// Navigating to a person (from a face at the table, Family, or a cook).
struct PersonRoute: Hashable {
    let name: String
}

/// The family's history told through one person: every Sunday they were
/// at the table, what they cook, and their recipes.
struct PersonView: View {
    let name: String

    @EnvironmentObject private var store: MealStore

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Meal.date, ascending: false)])
    private var meals: FetchedResults<Meal>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Rating.updatedAt, ascending: false)])
    private var ratings: FetchedResults<Rating>

    private func matches(_ other: String?) -> Bool {
        (other ?? "").trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame
    }

    /// Dinners they were at (or cooked), newest first.
    private var theirs: [Meal] {
        meals.filter { meal in
            !meal.isPlan && (matches(meal.cook) || meal.tablePeople.contains(where: matches))
        }
    }

    private var cooked: [Dish] {
        Suggestions.group(theirs.filter { matches($0.cook) }.compactMap { m -> MealSummary? in
            guard let id = m.id, let date = m.date else { return nil }
            return MealSummary(id: id, name: m.displayName, date: date, stars: nil)
        })
        .sorted { $0.timesEaten > $1.timesEaten }
    }

    private var recipes: [Meal] {
        var seen = Set<String>()
        return theirs.filter { matches($0.cook) && $0.recipe?.isEmpty == false }
            .filter { seen.insert(MealName.normalize($0.displayName)).inserted }
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14, alignment: .top)]

    var body: some View {
        let theirs = theirs
        let starsByMeal = MealStore.starsByMeal(ratings)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 10) {
                    CookAvatar(name: name, size: 96)
                    Text(name)
                        .font(.largeTitle.bold())
                        .keepsake()
                    Text("\(theirs.count) Sunday\(theirs.count == 1 ? "" : "s") at the table")
                        .font(.headline)
                    if let first = theirs.last?.date {
                        Text("First Sunday: \(first.formatted(.dateTime.month(.wide).day().year()))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .accessibilityElement(children: .combine)

                if !cooked.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What \(name) cooks")
                            .font(.title3.weight(.semibold))
                            .keepsake()
                        ForEach(cooked.prefix(6)) { dish in
                            HStack {
                                Text(dish.displayName).keepsake()
                                Spacer()
                                Text("\(dish.timesEaten)×")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .font(.body)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if !recipes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(name)'s recipes")
                            .font(.title3.weight(.semibold))
                            .keepsake()
                        ForEach(recipes) { meal in
                            NavigationLink(value: meal.objectID) {
                                HStack {
                                    Label(meal.displayName, systemImage: meal.recipeAudio == nil ? "book.closed" : "waveform")
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if !theirs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Their Sundays")
                            .font(.title3.weight(.semibold))
                            .keepsake()
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(theirs) { meal in
                                CompactMealCard(meal: meal, stars: meal.id.flatMap { starsByMeal[$0] } ?? 0, showsCook: false)
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    /// Registers the destinations every stack in the app can push to.
    func sundayDestinations(store: MealStore) -> some View {
        navigationDestination(for: NSManagedObjectID.self) { id in
            if let meal = try? store.context.existingObject(with: id) as? Meal, !meal.isGone {
                MealDetailView(meal: meal)
            }
        }
        .navigationDestination(for: PersonRoute.self) { route in
            PersonView(name: route.name)
        }
    }
}
