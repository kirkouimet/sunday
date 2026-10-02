import CoreData
import SundayKit
import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var store: MealStore

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Meal.date, ascending: false)], animation: .default)
    private var meals: FetchedResults<Meal>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Rating.updatedAt, ascending: false)])
    private var ratings: FetchedResults<Rating>

    @State private var searchText = ""
    @State private var seasonFilter: Season?
    @State private var isAdding = false

    private var starsByMeal: [UUID: Int] {
        Dictionary(ratings.compactMap { r in r.mealID.map { ($0, Int(r.stars)) } }, uniquingKeysWith: { a, _ in a })
    }

    private var filteredMeals: [Meal] {
        let query = MealName.normalize(searchText)
        return meals.filter { meal in
            if let seasonFilter, meal.season != seasonFilter { return false }
            guard !query.isEmpty else { return true }
            let haystack = MealName.normalize([meal.name, meal.cook, meal.notes].compactMap { $0 }.joined(separator: " "))
            return haystack.contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if !meals.isEmpty {
                    seasonPicker
                }
                LazyVStack(spacing: 20) {
                    ForEach(filteredMeals) { meal in
                        NavigationLink(value: meal.objectID) {
                            MealCard(meal: meal, stars: meal.id.flatMap { starsByMeal[$0] } ?? 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .overlay { emptyState }
            .navigationTitle("Sunday")
            .navigationDestination(for: NSManagedObjectID.self) { id in
                if let meal = try? store.context.existingObject(with: id) as? Meal {
                    MealDetailView(meal: meal)
                }
            }
            .searchable(text: $searchText, prompt: "Search dinners")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Add dinner", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $isAdding) {
                MealEditorView()
            }
        }
    }

    private var seasonPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                chip(title: "All", isSelected: seasonFilter == nil) { seasonFilter = nil }
                ForEach(Season.allCases) { season in
                    chip(title: "\(season.emoji) \(season.displayName)", isSelected: seasonFilter == season) {
                        seasonFilter = seasonFilter == season ? nil : season
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.sundayAccent : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var emptyState: some View {
        if meals.isEmpty {
            ContentUnavailableView {
                Label("No dinners yet", systemImage: "fork.knife")
            } description: {
                Text("Snap a picture of this Sunday's dinner to start your family's record.")
            } actions: {
                Button("Add your first dinner") { isAdding = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if filteredMeals.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }
}

struct MealCard: View {
    @ObservedObject var meal: Meal
    let stars: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PhotoThumbnail(photo: meal.sortedPhotos.first)
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topLeading) {
                    SeasonBadge(season: meal.season).padding(10)
                }
                .overlay(alignment: .bottomTrailing) {
                    if meal.sortedPhotos.count > 1 {
                        Label("\(meal.sortedPhotos.count)", systemImage: "photo.on.rectangle")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                            .padding(10)
                    }
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(meal.displayName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                HStack {
                    Text((meal.date ?? .now).dinnerFormatted)
                    if let cook = meal.cook, !cook.isEmpty {
                        Text("· by \(cook)")
                    }
                    Spacer()
                    if stars > 0 {
                        StarsLabel(stars: Double(stars))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .contentShape(Rectangle())
    }
}

#Preview {
    FeedView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(MealStore(persistence: .preview))
}
