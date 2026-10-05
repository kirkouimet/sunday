import SundayKit
import SwiftUI

/// Asks sunday.cooking whether this build is still new enough, and remembers
/// the last answer so an old build stays stopped without a connection. With
/// no answer at all (offline, no file yet) the app simply carries on.
@MainActor
final class UpdateGate: ObservableObject {
    @Published private(set) var settings: AppSettings?

    private static let cacheKey = "appSettings"
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

    init() {
        guard !PersistenceController.isUITesting else { return }
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey) {
            settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        }
    }

    var updateRequired: Bool { settings?.requiresUpdate(from: version) ?? false }

    func refresh() async {
        guard !PersistenceController.isUITesting else { return }
        var request = URLRequest(url: AppSettings.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let fetched = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return }
        settings = fetched
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }
}

/// Covers the whole app when this build is too old. The dinners are safe on
/// the phone and in iCloud; they're back as soon as the update is installed.
struct UpdateRequiredView: View {
    let settings: AppSettings?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label("Time to update Sunday", systemImage: "arrow.down.circle")
        } description: {
            Text(settings?.message ?? "This version is too old to keep your family's dinners in step. Your dinners are safe and will be here after you update.")
        } actions: {
            if let url = settings?.updateURL {
                Button("Update") { openURL(url) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .interactiveDismissDisabled()
    }
}
