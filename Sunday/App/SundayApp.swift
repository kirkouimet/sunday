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
            store.reconcile()
            Task {
                await store.refreshAccountStatus()
                await Reminders.rescheduleIfEnabled(store: store)
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: MealStore

    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Dinners", systemImage: "fork.knife") }
            SuggestView()
                .tabItem { Label("Ideas", systemImage: "sparkles") }
            FamilyView()
                .tabItem { Label("Family", systemImage: "person.3") }
        }
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

extension Color {
    static let sundayAccent = Color("AccentColor")
}
