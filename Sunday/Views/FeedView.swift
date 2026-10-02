import CoreData
import PhotosUI
import SundayKit
import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var store: MealStore
    @EnvironmentObject private var router: AppRouter

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Meal.date, ascending: false)], animation: .default)
    private var meals: FetchedResults<Meal>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Rating.updatedAt, ascending: false)])
    private var ratings: FetchedResults<Rating>

    @State private var searchText = ""
    @State private var seasonFilter: Season?
    @State private var isAdding = false
    @State private var editingMeal: Meal?
    /// "Dinner wrapped up · Undo", for a few seconds after That's dinner.
    @State private var toast: UndoToast?
    /// Snap from the Live card: camera straight onto that dinner.
    @State private var snappingLive: Meal?
    @State private var livePickerItem: PhotosPickerItem?
    /// "That's dinner" tapped here, not yet sent (Undo is still up).
    @State private var pendingEnd: Meal?
    @State private var endTimer: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    private var isFiltering: Bool { seasonFilter != nil || !MealName.normalize(searchText).isEmpty }

    /// Planned dinners aren't history until someone snaps or confirms them.
    static func isPlanned(_ meal: Meal) -> Bool { meal.isPlan }


    private var filteredMeals: [Meal] {
        let query = MealName.normalize(searchText)
        return meals.filter { meal in
            if Self.isPlanned(meal) { return false }
            if let seasonFilter, meal.season != seasonFilter { return false }
            guard !query.isEmpty else { return true }
            let tags = FoodTags.decode(meal.tags).map(FoodTags.displayName)
            let haystack = MealName.normalize(([meal.name, meal.cook, meal.notes].compactMap { $0 } + tags).joined(separator: " "))
            return haystack.contains(query)
        }
    }

    /// Feed grouped by year, newest first, so years of Sundays read like an album.
    private func mealsByYear(_ meals: [Meal]) -> [(year: Int, meals: [Meal])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: meals) { calendar.component(.year, from: $0.date ?? .now) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    private var streak: Int {
        SundayCalendar.streak(mealDates: meals.filter { !$0.isPlan }.compactMap(\.date))
    }

    private func memory(starsByMeal: [UUID: Int]) -> MealSummary? {
        let summaries = meals.compactMap { meal -> MealSummary? in
            guard let id = meal.id, let date = meal.date else { return nil }
            return MealSummary(id: id, name: meal.displayName, date: date, stars: starsByMeal[id])
        }
        return Suggestions(meals: summaries, hemisphere: .current).thisTimeInPastYears(windowDays: 7).first
    }

    /// What this week asks of you, in order: follow up on a plan that came
    /// and went, show the plan, celebrate a rating you just gave, or invite
    /// the next Sunday. Rating itself lives on the dinner's own card.
    private func tonight(starsByMeal: [UUID: Int], dishes: [Dish]) -> TonightCard.Mode? {
        guard !isFiltering else { return nil }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: .now)
        func meal(on day: Date) -> Meal? {
            meals.first { $0.date.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
        }

        // Dinner is happening right now.
        // The first one started, matching the Lock Screen and the store.
        if let live = meals.filter(\.isLive).min(by: { ($0.liveAt ?? .distantFuture) < ($1.liveAt ?? .distantFuture) }) {
            return .live(live)
        }
        // A plan whose day has passed without a photo: "Did you have Chili?"
        if let stale = meals.first(where: { $0.isPlan && ($0.date ?? .distantFuture) < startOfToday }) {
            return .followUp(stale)
        }
        if SundayCalendar.isSunday(.now) {
            guard let tonight = meal(on: .now) else { return .log }
            if tonight.isPlan { return .planned(tonight, isToday: true) }
            // Snapped tonight without going live, while everyone's still here.
            if store.role != .solo, tonight.liveAt == nil, calendar.component(.hour, from: .now) >= 15,
               Date.now.timeIntervalSince(tonight.createdAt ?? .distantPast) < 3 * 3600 {
                return .goLive(tonight)
            }
            return nil
        }
        if let plan = meal(on: SundayCalendar.upcomingSunday(onOrAfter: .now)), plan.isPlan {
            return .planned(plan, isToday: false)
        }
        return meal(on: SundayCalendar.mostRecentSunday(onOrBefore: .now)) == nil ? .missed : .plan
    }

    private func insight(for meal: Meal, dishes: [Dish]) -> String? {
        guard let id = meal.id, let dish = dishes.first(where: { $0.key == MealName.normalize(meal.displayName) }) else { return nil }
        return PersonalInsight.line(for: id, in: dish)
    }

    private let gridColumns = [GridItem(.adaptive(minimum: 160), spacing: 14, alignment: .top)]

    var body: some View {
        // Computed once per render rather than per card.
        let starsByMeal = MealStore.starsByMeal(ratings)
        let filtered = filteredMeals
        let memoryItem = isFiltering || meals.isEmpty ? nil : memory(starsByMeal: starsByMeal)
        // While dinner is live, its photos are on the Live card, not twice.
        let shown = isFiltering ? filtered : filtered.filter { !$0.isLive }
        let featured = isFiltering ? nil : shown.first
        let rest = featured == nil ? shown : Array(shown.dropFirst())
        let dishes = Suggestions.group(store.summaries(meals: Array(meals), ratings: Array(ratings)))
        let mode = meals.isEmpty ? nil : tonight(starsByMeal: starsByMeal, dishes: dishes)
        let cooks = store.familyNames(from: Array(meals))
        let bottomMargin: CGFloat = { if case .live? = mode { return 120 } else { return 72 } }()

        NavigationStack(path: $router.feedPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch mode {
                    case .live(let meal)?:
                        // Ended on this phone, waiting out the Undo: the family
                        // hears nothing until it's final.
                        if meal.objectID != pendingEnd?.objectID {
                            LiveDinnerCard(meal: meal, onSnap: { snappingLive = meal }) { ended in
                                withAnimation {
                                    pendingEnd = ended
                                    toast = UndoToast(text: "That's dinner", undo: {
                                        endTimer?.cancel()
                                        pendingEnd = nil
                                    })
                                    // Its own timer: another toast or a tab switch can't hold it back.
                                    endTimer?.cancel()
                                    endTimer = Task {
                                        try? await Task.sleep(for: .seconds(6))
                                        guard !Task.isCancelled else { return }
                                        commitPendingEnd()
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    case .goLive(let meal)?:
                        GoLiveBanner {
                            if store.myName == nil { router.askWhoIAm = true } else { store.startLive(meal) }
                        }
                            .padding(.horizontal)
                    case .some(let mode):
                        TonightCard(mode: mode, memory: memoryItem, cooks: cooks, streak: streak) { isAdding = true }
                            .padding(.horizontal)
                    case nil:
                        EmptyView()
                    }

                    if let featured {
                        card(for: featured, stars: featured.id.flatMap { starsByMeal[$0] } ?? 0,
                             showsCook: cooks.count > 1, compactHero: mode != nil,
                             insight: insight(for: featured, dishes: dishes))
                            .padding(.horizontal)
                    }

                    // Skip the memory card when the plan card is already telling it.
                    if let memoryItem, mode?.isPlanWithMemory != true, let meal = meals.first(where: { $0.id == memoryItem.id }) {
                        OnThisDayCard(meal: meal, summary: memoryItem)
                            .padding(.horizontal)
                    }

                    // Season filters earn their place once there are years of dinners.
                    if meals.count >= 24 {
                        seasonPicker
                    }

                    ForEach(mealsByYear(rest), id: \.year) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            yearHeader(group.year, count: group.meals.count)
                            LazyVGrid(columns: gridColumns, spacing: 14) {
                                ForEach(group.meals) { meal in
                                    compactCard(for: meal, stars: meal.id.flatMap { starsByMeal[$0] } ?? 0,
                                                showsCook: cooks.count > 1)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
            // Room for the Live card's footer above the floating tab bar.
            .contentMargins(.bottom, bottomMargin, for: .scrollContent)
            .background(Color(.systemGroupedBackground))
            .overlay { emptyState(filtered: filtered) }
            .overlay(alignment: .bottom) {
                if let toast {
                    HStack {
                        Text(toast.text).font(.subheadline.weight(.medium)).lineLimit(1)
                        Spacer()
                        Button("Undo") {
                            toast.undo()
                            withAnimation { self.toast = nil }
                        }
                        .bold()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.horizontal)
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(6))
                        guard !Task.isCancelled else { return }
                        withAnimation { self.toast = nil }
                    }
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { snappingLive != nil && CameraPicker.isAvailable },
                set: { if !$0 { snappingLive = nil } }
            )) {
                CameraPicker { image in
                    if let meal = snappingLive { addLivePhoto(image, to: meal) }
                }
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: Binding(
                get: { snappingLive != nil && !CameraPicker.isAvailable },
                set: { if !$0 { snappingLive = nil } }
            ), selection: $livePickerItem, matching: .images)
            .onChange(of: livePickerItem) { _, item in
                guard let item, let meal = snappingLive else { return }
                livePickerItem = nil
                snappingLive = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        addLivePhoto(image, to: meal)
                    }
                }
            }
            .navigationTitle("Sunday")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAdding = true
                    } label: {
                        Label("Add dinner", systemImage: "plus")
                    }
                    .accessibilityIdentifier("addDinner")
                }
            }
            .sundayDestinations(store: store)
            .searchable(text: $searchText, prompt: "Search dinners, cooks, food")
            .sheet(isPresented: $isAdding) {
                MealEditorView()
            }
            .onChange(of: router.snapRequested) { _, requested in
                guard requested else { return }
                router.snapRequested = false
                // From the Lock Screen or the "dinner is on" notification:
                // during Live that's a photo for the table, not a new dinner.
                if let live = store.liveMeal() {
                    snappingLive = live
                } else {
                    isAdding = true
                }
            }
            .sheet(item: $editingMeal) { meal in
                MealEditorView(meal: meal)
            }
            .onChange(of: scenePhase) { _, phase in
                // Leaving the app makes "That's dinner" final.
                if phase != .active, pendingEnd != nil {
                    commitPendingEnd()
                    toast = nil
                }
            }
        }
    }

    private func commitPendingEnd() {
        endTimer?.cancel()
        endTimer = nil
        guard let meal = pendingEnd else { return }
        pendingEnd = nil
        store.endLive(meal)
    }

    private func addLivePhoto(_ image: UIImage, to meal: Meal) {
        Task {
            guard let photo = await store.addLivePhoto(image, to: meal) else { return }
            withAnimation {
                let text = Connectivity.shared.isOnline
                    ? "Added to \(meal.displayName)"
                    : "Saved. Sends when you're back online"
                toast = UndoToast(text: text, undo: { store.deletePhoto(photo) })
            }
        }
    }

    private func card(for meal: Meal, stars: Int, showsCook: Bool, compactHero: Bool, insight: String?) -> some View {
        MealCard(meal: meal, stars: stars, showsCook: showsCook, compactHero: compactHero, insight: insight)
            .contextMenu { contextMenu(for: meal) }
    }

    private func compactCard(for meal: Meal, stars: Int, showsCook: Bool) -> some View {
        CompactMealCard(meal: meal, stars: stars, showsCook: showsCook)
            .contextMenu { contextMenu(for: meal) }
    }

    /// Everyone who has cooked, most frequent first.
    static func cooks(in meals: [Meal]) -> [String] {
        var counts: [String: (name: String, count: Int)] = [:]
        for cook in meals.compactMap({ $0.cook?.trimmingCharacters(in: .whitespaces) }) where !cook.isEmpty {
            counts[cook.lowercased(), default: (cook, 0)].count += 1
        }
        return counts.values.sorted { $0.count > $1.count }.map(\.name)
    }

    @ViewBuilder
    private func contextMenu(for meal: Meal) -> some View {
        if store.canEdit(meal) {
            Button {
                editingMeal = meal
            } label: {
                Label("Edit", systemImage: "pencil")
            }
        }
    }

    private func yearHeader(_ year: Int, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(year))
                .font(.title2.bold())
                .keepsake()
            Text("\(count) dinner\(count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.top, 8)
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
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.primary.opacity(0.85) : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func emptyState(filtered: [Meal]) -> some View {
        if meals.isEmpty {
            ContentUnavailableView {
                Label("No dinners yet", systemImage: "fork.knife")
            } description: {
                Text("Snap a photo of this Sunday's dinner to start your family's record.")
            } actions: {
                Button("Add your first dinner") { isAdding = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }
}

/// The week's one job, front and center: plan it, snap it, rate it, and
/// then, the morning after, remember it.
struct TonightCard: View {
    enum Mode {
        case log
        case missed
        case plan
        case planned(Meal, isToday: Bool)
        case followUp(Meal)
        case live(Meal)
        /// Tonight's dinner was just snapped without going live: offer it.
        case goLive(Meal)

        var isPlanWithMemory: Bool {
            if case .plan = self { return true }
            return false
        }
    }

    let mode: Mode
    let memory: MealSummary?
    let cooks: [String]
    var streak = 0
    var onAdd: () -> Void

    @EnvironmentObject private var store: MealStore
    @EnvironmentObject private var router: AppRouter
    @State private var stars = 0
    /// "We're sitting down" on a phone that hasn't said whose it is.
    @State private var startAfterNaming: (() -> Void)?

    private var snapButton: some View {
        Button(action: onAdd) {
            Label("Snap a photo", systemImage: "camera.fill")
                .frame(maxWidth: .infinity)
        }
    }

    /// Dinner is started by a person: ask "Which one are you?" first if needed.
    private func whenNamed(_ action: @escaping () -> Void) {
        if store.myName == nil {
            startAfterNaming = action
        } else {
            action()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch mode {
            case .log:
                Text("It's Sunday.\nWhat's cooking?")
                    .font(.title.bold())
                    .keepsake()
                if let memory {
                    Text("Last year this week: \(memory.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                // With a family, Sunday starts with sitting down together
                // (Live has its own Snap); alone, it's just the photo.
                if store.role != .solo {
                    Button {
                        whenNamed { Task { try? await store.startLiveTonight() } }
                    } label: {
                        Label("We're sitting down", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("Lets everyone in the family check in and add photos to tonight's dinner.")
                    .disabled(!store.isFreshFromFamily)
                    .overlay {
                        if !store.isFreshFromFamily { CheckingOverlay() }
                    }
                    }
                }
                if store.role == .solo {
                    snapButton.buttonStyle(.borderedProminent).controlSize(.large)
                } else {
                    snapButton.buttonStyle(.bordered).controlSize(.large)
                }
                // Deciding is for the afternoon; by dinnertime it's noise.
                if Calendar.current.component(.hour, from: .now) < 15 {
                    Button("Ideas") { router.showIdeas = true }
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("ideasButton")
                }

            case .missed:
                Text("Missed last Sunday?")
                    .font(.title3.bold())
                    .keepsake()
                Text("Add it from the camera roll. The date comes from the photo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: onAdd) {
                    Label("Add last Sunday's dinner", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)

            case .plan:
                if let memory {
                    // The memory *is* the idea: one card instead of three.
                    Text(memoryCaption(memory))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.sundayAccent)
                    Text("\(memory.name). Again this Sunday?")
                        .font(.title3.bold())
                        .keepsake()
                        .lineLimit(3)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { planButtons(memory) }
                        VStack(alignment: .leading, spacing: 8) { planButtons(memory) }
                    }
                } else {
                    Text("What's for Sunday?")
                        .font(.title3.bold())
                        .keepsake()
                    Text("Pick a dinner and who's cooking. On Sunday, one photo and you're done.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        router.showIdeas = true
                    } label: {
                        Label("Ideas", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("ideasButton")
                }

            case .planned(let meal, let isToday):
                Text(isToday ? "Tonight" : "This Sunday")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.sundayAccent)
                Text(meal.displayName)
                    .font(.title2.bold())
                    .keepsake()
                    .lineLimit(2)
                cookPicker(for: meal)
                if !isToday {
                    Button("Change the plan") { router.showIdeas = true }
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("ideasButton")
                }
                if isToday {
                    Button(action: onAdd) {
                        Label("Snap a photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    // Sunday Live: the whole family checks in and snaps.
                    if store.role != .solo {
                    Button {
                        whenNamed { store.startLive(meal) }
                    } label: {
                        Label("We're sitting down", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityHint("Lets everyone in the family check in and add photos to tonight's dinner.")
                    .disabled(!store.isFreshFromFamily)
                    .overlay {
                        if !store.isFreshFromFamily { CheckingOverlay() }
                    }
                }

            case .live, .goLive:
                EmptyView() // Shown by FeedView as the hero card / in the hero.

            case .followUp(let meal):
                Text("Did you have \(meal.displayName)?")
                    .font(.title3.bold())
                    .keepsake()
                Text("It was the plan for \((meal.date ?? .now).formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { followUpButtons(meal) }
                    VStack(alignment: .leading, spacing: 8) { followUpButtons(meal) }
                }

            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.sundayAccent.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .sheet(isPresented: Binding(get: { startAfterNaming != nil }, set: { if !$0 { startAfterNaming = nil } })) {
            WhichOneAreYouView { name in
                let start = startAfterNaming
                startAfterNaming = nil
                store.setMyName(name)
                start?()
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func followUpButtons(_ meal: Meal) -> some View {
        Button(action: onAdd) {
            Label("Add the photo", systemImage: "photo.on.rectangle")
        }
        .buttonStyle(.borderedProminent)
        Button("Yes, no photo") { store.confirmPlan(meal, eaten: true) }
            .buttonStyle(.bordered)
        Button("We didn't") { store.confirmPlan(meal, eaten: false) }
            .buttonStyle(.bordered)
            .tint(.secondary)
    }

    @ViewBuilder
    private func planButtons(_ memory: MealSummary) -> some View {
        Button {
            Task { try? await store.planSunday(memory.name) }
        } label: {
            Text("Make it Sunday").fixedSize()
        }
        .buttonStyle(.borderedProminent)
        Button {
            router.showIdeas = true
        } label: {
            Text("Ideas").fixedSize()
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("ideasButton")
    }

    private func memoryCaption(_ memory: MealSummary) -> String {
        let years = SundayCalendar.yearsAgo(memory.date)
        return years == 1 ? "A year ago this week" : "\(years) years ago this week"
    }

    /// "Who's cooking?" Tap a person; it syncs to the family right away.
    private func cookPicker(for meal: Meal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Who's cooking?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(cooks, id: \.self) { cook in
                        let selected = (meal.cook ?? "").caseInsensitiveCompare(cook) == .orderedSame
                        Button {
                            store.setCook(selected ? nil : cook, for: meal)
                        } label: {
                            HStack(spacing: 6) {
                                CookAvatar(name: cook, size: 26)
                                Text(cook).font(.subheadline.weight(.medium))
                            }
                            .padding(.leading, 4)
                            .padding(.trailing, 12)
                            .padding(.vertical, 5)
                            .background(selected ? Color.sundayAccent.opacity(0.18) : Color.secondary.opacity(0.1), in: Capsule())
                            .overlay(Capsule().strokeBorder(selected ? Color.sundayAccent : .clear, lineWidth: 1.5))
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }
}

/// The latest dinner, big.
struct MealCard: View {
    @ObservedObject var meal: Meal
    let stars: Int
    var showsCook = true
    /// Shorter photo when a Tonight card sits above, so the title and stars
    /// stay above the tab bar.
    var compactHero = false
    /// "Your 3rd lemon chicken…": shown under your stars once you've rated.
    var insight: String?

    @EnvironmentObject private var store: MealStore
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isRecent: Bool {
        guard let date = meal.date else { return false }
        return Date.now.timeIntervalSince(date) < 7 * 86_400
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            link
            if stars == 0, isRecent {
                Divider().padding(.horizontal, 16)
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                    : AnyLayout(HStackLayout())
                layout {
                    Text("How was it?")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    if !typeSize.isAccessibilitySize { Spacer() }
                    StarRatingView(stars: Binding(
                        get: { stars },
                        set: { store.setRating($0, for: meal) }
                    ), size: 22)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            } else if stars > 0, isRecent, let insight {
                // The table remembers: a private line, right where you rated.
                Divider().padding(.horizontal, 16)
                Label {
                    Text(insight).italic().keepsake()
                } icon: {
                    Image(systemName: "lock.fill").font(.caption)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityLabel("Just for you: \(insight)")
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    private var link: some View {
        NavigationLink(value: meal.objectID) {
            VStack(alignment: .leading, spacing: 0) {
                PhotoThumbnail(photo: meal.sortedPhotos.first)
                    .aspectRatio(compactHero ? 5 / 3 : 4 / 3, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topLeading) {
                        OccasionBadge(meal: meal).padding(10)
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

                VStack(alignment: .leading, spacing: 8) {
                    Text(meal.displayName)
                        .font(.title2.weight(.semibold))
                        .keepsake()
                        .lineLimit(2)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            meta
                            Spacer(minLength: 4)
                            rating
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            meta
                            rating
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("heroCard")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mealAccessibilityText(meal))
        .accessibilityValue(stars > 0 ? "Your rating, \(starsDescription(Double(stars)))" : "Not rated")
        .accessibilityHint("Shows photos and history")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var meta: some View {
        HStack(spacing: 8) {
            Text((meal.date ?? .now).dinnerFormatted)
            if showsCook, let cook = meal.cook, !cook.isEmpty {
                CookLabel(name: cook, size: 20)
            }
        }
    }

    @ViewBuilder
    private var rating: some View {
        if stars > 0 {
            CompactStars(stars: Double(stars))
        }
    }
}

/// Older dinners: a photo-first tile in a grid, so years stay browsable.
struct CompactMealCard: View {
    @ObservedObject var meal: Meal
    let stars: Int
    var showsCook = true

    var body: some View {
        NavigationLink(value: meal.objectID) {
            VStack(alignment: .leading, spacing: 8) {
                PhotoThumbnail(photo: meal.sortedPhotos.first)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityHidden(true)
                Text(meal.displayName)
                    .font(.headline)
                    .keepsake()
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text((meal.date ?? .now).formatted(.dateTime.month(.abbreviated).day()))
                    if showsCook, let cook = meal.cook, !cook.isEmpty {
                        CookAvatar(name: cook, size: 16)
                    }
                    Spacer(minLength: 0)
                    if stars > 0 { CompactStars(stars: Double(stars)) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("mealCard")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mealAccessibilityText(meal))
        .accessibilityValue(stars > 0 ? "Your rating, \(starsDescription(Double(stars)))" : "Not rated")
        .accessibilityAddTraits(.isButton)
    }
}

func mealAccessibilityText(_ meal: Meal) -> String {
    var parts = [meal.displayName, (meal.date ?? .now).dinnerFormatted]
    if let cook = meal.cook, !cook.isEmpty { parts.append("cooked by \(cook)") }
    parts.append(meal.holiday?.name ?? meal.season.displayName)
    let count = meal.sortedPhotos.count
    if count > 1 { parts.append("\(count) photos") }
    return parts.joined(separator: ", ")
}

/// "A year ago this week" memory at the top of the feed.
struct OnThisDayCard: View {
    @ObservedObject var meal: Meal
    let summary: MealSummary
    @Environment(\.dynamicTypeSize) private var typeSize

    private var whenText: String {
        let years = SundayCalendar.yearsAgo(summary.date)
        return years == 1 ? "A year ago this week" : "\(years) years ago this week"
    }

    var body: some View {
        NavigationLink(value: meal.objectID) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(spacing: 14))
            layout {
                PhotoThumbnail(photo: meal.sortedPhotos.first)
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(whenText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.sundayAccent)
                    Text(summary.name)
                        .font(.headline)
                        .keepsake()
                        .lineLimit(2)
                    Text(summary.date.dinnerFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.sundayAccent.opacity(0.35), lineWidth: 1)
            )
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

/// "Everyone still at the table?" after tonight's photo, if dinner
/// wasn't started live: one tap lets the family check in and add theirs.
struct GoLiveBanner: View {
    var action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title3)
                .foregroundStyle(Color.sundayAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Everyone still at the table?")
                    .font(.subheadline.weight(.semibold))
                Text("So everyone can check in and add photos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("We're sitting down", action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// "Dinner wrapped up · Undo", "Added to Chili · Undo".
struct UndoToast: Identifiable {
    let id = UUID()
    let text: String
    let undo: () -> Void
}

/// Over "We're sitting down" while a phone opened late catches up, so it
/// can't restart a dinner someone else already started.
struct CheckingOverlay: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Checking with the family…").font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemGroupedBackground).opacity(0.92), in: Capsule())
        .allowsHitTesting(false)
    }
}
