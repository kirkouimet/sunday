import CloudKit
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        FamilyNotifier.registerCategories()
        // "I'm here" from a Live Activity or notification, applied right away.
        CheckInIntent.onCheckIn = { MealStore.shared.applyPendingCheckIns() }
        // Silent pushes let CloudKit sync (and us notice new family dinners)
        // in the background.
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// Receives "Join Sunday Dinners" taps from the iCloud invite link.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Invite tapped while the app wasn't running: the metadata arrives at launch.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        accept(metadata)
    }

    /// Invite tapped while the app was already running.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        accept(metadata)
    }

    private func accept(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            await MealStore.shared.acceptShare(metadata)
        }
    }
}
