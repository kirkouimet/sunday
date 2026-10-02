import CloudKit
import CoreData
import os

/// Two SQLite stores, both mirrored to iCloud by NSPersistentCloudKitContainer:
///
/// - **private**: your own iCloud database. Holds your private ratings (default
///   zone, never shared) and, if you started the family, the family's meals and
///   photos (in the share's zone).
/// - **shared**: dinners from a family someone else invited you to.
///
/// A fetch on `viewContext` reads both stores, so the feed just works for
/// owners and participants alike.
final class PersistenceController {
    static let cloudKitContainerID = "iCloud.com.kirkouimet.sunday"
    /// UI tests (and screenshot runs) get an in-memory store full of sample dinners.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
    static let shared = isUITesting ? preview : PersistenceController()

    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        PreviewData.populate(controller.container.viewContext)
        return controller
    }()

    let container: NSPersistentCloudKitContainer
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?
    let isCloudBacked: Bool

    private let logger = Logger(subsystem: "com.kirkouimet.sunday", category: "persistence")

    var ckContainer: CKContainer { CKContainer(identifier: Self.cloudKitContainerID) }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Sunday", managedObjectModel: SundayModel.shared)
        isCloudBacked = !inMemory

        let directory = NSPersistentContainer.defaultDirectoryURL()
        let privateURL = inMemory ? URL(fileURLWithPath: "/dev/null") : directory.appendingPathComponent("private.sqlite")
        let sharedURL = directory.appendingPathComponent("shared.sqlite")

        let privateDescription = NSPersistentStoreDescription(url: privateURL)
        var descriptions = [privateDescription]

        if !inMemory {
            let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerID)
            privateOptions.databaseScope = .private
            privateDescription.cloudKitContainerOptions = privateOptions

            let sharedDescription = NSPersistentStoreDescription(url: sharedURL)
            let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainerID)
            sharedOptions.databaseScope = .shared
            sharedDescription.cloudKitContainerOptions = sharedOptions
            descriptions.append(sharedDescription)
        }

        for description in descriptions {
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        container.persistentStoreDescriptions = descriptions

        container.loadPersistentStores { [logger] description, error in
            if let error {
                // Losing the family's dinners silently would be worse than a crash
                // during development; surface it loudly.
                logger.fault("Failed to load store \(description.url?.lastPathComponent ?? "?"): \(error.localizedDescription)")
                fatalError("Failed to load store: \(error)")
            }
        }

        let coordinator = container.persistentStoreCoordinator
        privateStore = coordinator.persistentStore(for: privateURL)
        sharedStore = inMemory ? nil : coordinator.persistentStore(for: sharedURL)

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.transactionAuthor = "app"
        // Query generations need a real SQLite file; the in-memory store used
        // by previews and UI tests throws on every save if this is set.
        if !inMemory {
            try? container.viewContext.setQueryGenerationFrom(.current)
        }

        #if DEBUG
        // Pushes the schema to the CloudKit *development* environment once.
        // Before shipping, deploy it to production in the CloudKit console.
        if !inMemory, ProcessInfo.processInfo.environment["SUNDAY_INIT_CLOUDKIT_SCHEMA"] == "1" {
            do {
                try container.initializeCloudKitSchema(options: [])
            } catch {
                logger.error("initializeCloudKitSchema failed: \(error.localizedDescription)")
            }
        }
        #endif
    }
}
