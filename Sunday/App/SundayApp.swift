import SwiftUI

@main
struct SundayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = MealStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, store.context)
                .environmentObject(store)
                .tint(.sundayAccent)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.refreshShare()
            Task {
                await store.refreshAccountStatus()
                await Reminders.rescheduleIfEnabled(store: store)
            }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Dinners", systemImage: "fork.knife") }
            SuggestView()
                .tabItem { Label("What's for dinner?", systemImage: "sparkles") }
            FamilyView()
                .tabItem { Label("Family", systemImage: "person.3") }
        }
    }
}

extension Color {
    static let sundayAccent = Color("AccentColor")
}
