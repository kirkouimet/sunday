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
    @State private var editingMeal: Meal?
    @EnvironmentObject private var router: AppRouter

    private var starsByMeal: [UUID: Int] { MealStore.starsByMeal(ratings) }

    private var isFiltering: Bool { seasonFilter != nil || !MealName.normalize(searchText).isEmpty }

    private var filteredMeals: [Meal] {
        let query = MealName.normalize(searchText)
        return meals.filter { meal in
            if let seasonFilter, meal.season != seasonFilter { return false }
            guard !query.isEmpty else { return true }
            let haystack = MealName.normalize([meal.name, meal.cook, meal.notes].compactMap { $0 }.joined(separator: " "))
            return haystack.contains(query)
        }
    }

    /// Feed grouped by year, newest first, so years of Sundays read like an album.
    private var mealsByYear: [(year: Int, meals: [Meal])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredMeals) { calendar.component(.year, from: $0.date ?? .now) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    private var streak: Int {
        SundayCalendar.streak(mealDates: meals.compactMap(\.date))
    }

    private var memory: MealSummary? {
        Suggestions(meals: store.summaries(meals: Array(meals), ratings: Array(ratings)), hemisphere: .current)
            .thisTimeInPastYears(windowDays: 7).first
    }

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 20, alignment: .top)]

    var body: some View {
        NavigationStack(path: $router.feedPath) {
            ScrollView {
                if !meals.isEmpty {
                    seasonPicker
                    if !isFiltering, let memory, let meal = store.meal(withID: memory.id) {
                        OnThisDayCard(meal: meal, summary: memory)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                }
                LazyVGrid(columns: columns, spacing: 20, pinnedViews: [.sectionHeaders]) {
                    ForEach(mealsByYear, id: \.year) { group in
                        Section {
                            ForEach(group.meals) { meal in
                                card(for: meal)
                            }
                        } header: {
                            yearHeader(group.year, count: group.meals.count)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .overlay { emptyState }
            .navigationTitle("Sunday")
            .toolbar {
                if streak >= 2 {
                    ToolbarItem(placement: .topBarLeading) {
                        Label("\(streak) Sundays in a row", systemImage: "flame.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.sundayAccent)
                            .accessibilityLabel("\(streak) Sundays in a row")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Add dinner", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationDestination(for: NSManagedObjectID.self) { id in
                if let meal = try? store.context.existingObject(with: id) as? Meal, !meal.isGone {
                    MealDetailView(meal: meal)
                }
            }
            .searchable(text: $searchText, prompt: "Search dinners, cooks, notes")
            .sheet(isPresented: $isAdding) {
                MealEditorView()
            }
            .sheet(item: $editingMeal) { meal in
                MealEditorView(meal: meal)
            }
        }
    }

    private func card(for meal: Meal) -> some View {
        MealCard(meal: meal, stars: meal.id.flatMap { starsByMeal[$0] } ?? 0)
            .contextMenu {
                if store.canEdit(meal) {
                    Button {
                        editingMeal = meal
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }
            }
    }

    private func yearHeader(_ year: Int, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(year))
                .font(.title2.bold())
            Text("\(count) dinner\(count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .accessibilityAddTraits(.isHeader)
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
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentFill : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(isSelected ? Color.onAccentFill : Color.primary)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

    @EnvironmentObject private var store: MealStore

    /// Nudge everyone to rate recent dinners, right on the card.
    private var invitesRating: Bool {
        guard stars == 0, let date = meal.date else { return false }
        return Date.now.timeIntervalSince(date) < 7 * 86_400
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: meal.objectID) {
                summary
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("mealCard")

            if invitesRating {
                Divider().padding(.horizontal, 14)
                HStack {
                    Text("How was it?")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    StarRatingView(stars: Binding(
                        get: { stars },
                        set: { store.setRating($0, for: meal) }
                    ), size: 20)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
    }

    private var summary: some View {
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
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(meal.displayName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        meta
                        Spacer()
                        if stars > 0 { YourStarsLabel(stars: Double(stars)) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        meta
                        if stars > 0 { YourStarsLabel(stars: Double(stars)) }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityValue(stars > 0 ? "Your rating, \(starsDescription(Double(stars)))" : "Not rated")
            .accessibilityHint("Shows photos and history")
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var meta: some View {
        HStack(spacing: 4) {
            Text((meal.date ?? .now).dinnerFormatted)
            if let cook = meal.cook, !cook.isEmpty {
                Text("· cooked by \(cook)")
            }
        }
    }

    private var accessibilityText: String {
        var parts = [meal.displayName, (meal.date ?? .now).dinnerFormatted]
        if let cook = meal.cook, !cook.isEmpty { parts.append("cooked by \(cook)") }
        parts.append(meal.season.displayName)
        let count = meal.sortedPhotos.count
        if count > 1 { parts.append("\(count) photos") }
        return parts.joined(separator: ", ")
    }
}

/// "A year ago this week" memory at the top of the feed.
struct OnThisDayCard: View {
    @ObservedObject var meal: Meal
    let summary: MealSummary

    private var whenText: String {
        let years = max(1, Calendar.current.dateComponents([.year], from: summary.date, to: .now).year ?? 1)
        return years == 1 ? "A year ago this week" : "\(years) years ago this week"
    }

    var body: some View {
        NavigationLink(value: meal.objectID) {
            HStack(spacing: 14) {
                PhotoThumbnail(photo: meal.sortedPhotos.first)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Label(whenText, systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.sundayAccent)
                    Text(summary.name)
                        .font(.headline)
                        .lineLimit(2)
                    Text(summary.date.dinnerFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color.sundayAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(whenText): \(summary.name), \(summary.date.dinnerFormatted)")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    FeedView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(MealStore(persistence: .preview))
        .environmentObject(AppRouter())
}
