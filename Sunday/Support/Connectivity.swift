import Network
import SwiftUI

/// Whether this phone can reach iCloud right now, so a photo snapped in a
/// dead spot says it will send later instead of looking sent.
@MainActor
final class Connectivity: ObservableObject {
    static let shared = Connectivity()

    @Published private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in Connectivity.shared.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "cooking.sunday.Sunday.connectivity"))
    }
}
