import CoreData
import SundayKit
import SwiftUI

@main
struct SundayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = MealStore.shared
    @StateObject private var router = AppRouter()

    init() {
        // Keepsake type: large titles ("Sunday", "What's for dinner?") in New York.
        let largeTitle = UIFont.preferredFont(forTextStyle: .largeTitle)
        if let serif = largeTitle.fontDescriptor.withDesign(.serif)?.withSymbolicTraits(.traitBold) {
            UINavigationBar.appearance().largeTitleTextAttributes = [.font: UIFont(descriptor: serif, size: 0)]
        }
        let title = UIFont.preferredFont(forTextStyle: .headline)
        if let serif = title.fontDescriptor.withDesign(.serif)?.withSymbolicTraits(.traitBold) {
            UINavigationBar.appearance().titleTextAttributes = [.font: UIFont(descriptor: serif, size: 0)]
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, store.context)
                .environmentObject(store)
                .environmentObject(router)
                .onOpenURL { url in
                    guard let id = DeepLink.mealID(from: url), let meal = store.meal(withID: id) else { return }
                    router.show(meal)
                }
                .tint(.sundayAccent)
                .preferredColorScheme(UITestOptions.colorScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.reconcile()
            WidgetPublisher.publish(store: store)
            Task {
                await store.refreshAccountStatus()
                await Reminders.rescheduleIfEnabled(store: store)
            }
        }
    }
}

/// Which tab is showing and the feed's navigation stack, so deep links
/// (from the widget) can open a dinner.
@MainActor
final class AppRouter: ObservableObject {
    enum Tab: Hashable { case dinners, ideas, family }

    @Published var tab: Tab = .dinners
    @Published var feedPath: [NSManagedObjectID] = []

    func show(_ meal: Meal) {
        tab = .dinners
        feedPath = [meal.objectID]
    }
}

struct RootView: View {
    @EnvironmentObject private var store: MealStore
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        TabView(selection: $router.tab) {
            FeedView()
                .tabItem { Label("Dinners", systemImage: "fork.knife") }
                .tag(AppRouter.Tab.dinners)
            SuggestView()
                .tabItem { Label("Ideas", systemImage: "sparkles") }
                .tag(AppRouter.Tab.ideas)
            FamilyView()
                .tabItem { Label("Family", systemImage: "person.3") }
                .tag(AppRouter.Tab.family)
        }
        .minimizingTabBarOnScroll()
        .sheet(item: Binding(
            get: { store.milestone.map(Milestone.init) },
            set: { if $0 == nil { store.milestone = nil } }
        )) { milestone in
            MilestoneView(message: milestone.message)
                .presentationDetents([.medium])
        }
    }
}

private struct Milestone: Identifiable {
    let message: String
    var id: String { message }
}

struct MilestoneView: View {
    let message: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.sundayAccent)
                .symbolEffect(.bounce, value: bounce)
            Text(message)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Button("Keep it going") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .onAppear { if !reduceMotion { bounce.toggle() } }
        .sensoryFeedback(.success, trigger: bounce)
    }
}

extension View {
    /// iOS 26: tuck the tab bar away while scrolling through dinners.
    @ViewBuilder
    func minimizingTabBarOnScroll() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

enum UITestOptions {
    static var colorScheme: ColorScheme? {
        ProcessInfo.processInfo.arguments.contains("-uiDarkMode") ? .dark : nil
    }
}

extension Color {
    static let sundayAccent = Color("AccentColor")
}
