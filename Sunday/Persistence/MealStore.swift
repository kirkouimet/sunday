import CloudKit
import CoreData
import SundayKit
import UIKit
import os

/// What the add/edit screen hands to the store.
struct MealDraft {
    struct DraftPhoto: Identifiable {
        let id = UUID()
        var image: UIImage
        /// Set when this photo is already saved on the meal being edited.
        var existing: Photo?
    }

    var name = ""
    var date = Date.now
    var cook = ""
    var notes = ""
    var stars = 0
    var photos: [DraftPhoto] = []

    init() {}

    init(meal: Meal, stars: Int) {
        name = meal.name ?? ""
        date = meal.date ?? .now
        cook = meal.cook ?? ""
        notes = meal.notes ?? ""
        self.stars = stars
        // Keep every saved photo, even one whose image hasn't downloaded from
        // iCloud yet; dropping it here would delete it on save.
        photos = meal.sortedPhotos.map { photo in
            let image = (photo.thumbnailData ?? photo.imageData).flatMap(UIImage.init(data:))
                ?? UIImage(systemName: "photo") ?? UIImage()
            return DraftPhoto(image: image, existing: photo)
        }
    }

    /// Cheap equality for "are there unsaved changes?".
    var fingerprint: String {
        [name, cook, notes, "\(stars)", "\(date.timeIntervalSince1970)", photos.map(\.id.uuidString).joined(separator: ",")]
            .joined(separator: "|")
    }
}

enum FamilyRole: Equatable {
    /// No family share yet; everything is just in your own iCloud.
    case solo
    /// You created the family and invited people.
    case owner
    /// Someone else's family that you joined.
    case participant
}

@MainActor
final class MealStore: ObservableObject {
    static let shared = MealStore(persistence: .shared)

    let persistence: PersistenceController
    var context: NSManagedObjectContext { persistence.container.viewContext }

    @Published private(set) var share: CKShare?
    @Published private(set) var role: FamilyRole = .solo
    @Published private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    /// True once CloudKit has finished an import for *both* stores on this
    /// device. Until then we can't know whether this person already owns or
    /// joined a family (creating one would risk a duplicate), and ratings may
    /// have arrived before the dinners they belong to.
    @Published private(set) var hasCompletedFirstImport: Bool
    /// Set when a save crosses a milestone (1st, 50th, 100th dinner...).
    @Published var milestone: String?

    private static let importedStoresKey = "importedCloudKitStoreIdentifiers"
    private static let orphanedRatingsKey = "orphanedRatingsFirstSeen"
    /// How long a rating must point at a missing dinner before we delete it.
    private static let orphanGracePeriod: TimeInterval = 21 * 86_400
    private let logger = Logger(subsystem: "com.kirkouimet.sunday", category: "store")
    private var observers: [NSObjectProtocol] = []
    private var reconcileTask: Task<Void, Never>?
    private var sharingInFlight = Set<NSManagedObjectID>()
    private var sharedImportFallback: Task<Void, Never>?

    init(persistence: PersistenceController) {
        self.persistence = persistence
        hasCompletedFirstImport = false // every stored property set; now compute it
        hasCompletedFirstImport = !persistence.isCloudBacked || haveImportedAllStores
        refreshShare()
        observeCloudKit()
    }

    private var requiredStoreIdentifiers: Set<String> {
        Set([persistence.privateStore?.identifier, persistence.sharedStore?.identifier].compactMap { $0 })
    }

    private var importedStoreIdentifiers: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.importedStoresKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.importedStoresKey) }
    }

    private var haveImportedAllStores: Bool {
        let required = requiredStoreIdentifiers
        return !required.isEmpty && required.isSubset(of: importedStoreIdentifiers)
    }

    // MARK: Meals

    @discardableResult
    func save(_ draft: MealDraft, editing existing: Meal? = nil) async throws -> Meal {
        // Do the slow image work before touching the context, so a half-built
        // meal can never be committed by some other save in the meantime.
        var prepared: [UUID: ImageProcessing.Prepared] = [:]
        for draftPhoto in draft.photos where draftPhoto.existing == nil {
            prepared[draftPhoto.id] = await ImageProcessing.prepareAsync(draftPhoto.image)
        }

        if let existing, existing.isGone { throw SaveError.deletedElsewhere }

        let isNew = existing == nil
        let meal = existing ?? Meal(context: context)
        let store = existing?.objectID.persistentStore ?? storeForNewFamilyObjects

        if isNew {
            meal.id = UUID()
            meal.createdAt = .now
            if let store { context.assign(meal, to: store) }
        }
        meal.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        meal.date = draft.date
        meal.cook = draft.cook.trimmingCharacters(in: .whitespacesAndNewlines)
        meal.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)

        // Photos: drop removed ones, re-order kept ones, add new ones.
        let keptIDs = Set(draft.photos.compactMap { $0.existing?.objectID })
        for photo in meal.sortedPhotos where !keptIDs.contains(photo.objectID) {
            context.delete(photo)
        }
        for (index, draftPhoto) in draft.photos.enumerated() {
            if let photo = draftPhoto.existing {
                photo.sortIndex = Int16(index)
                continue
            }
            guard let images = prepared[draftPhoto.id] else { continue }
            let photo = Photo(context: context)
            photo.id = UUID()
            photo.createdAt = .now
            photo.sortIndex = Int16(index)
            photo.imageData = images.full
            photo.thumbnailData = images.thumbnail
            if let store { context.assign(photo, to: store) }
            photo.meal = meal
        }

        setRatingWithoutSaving(draft.stars, mealID: meal.id)

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        if isNew {
            FamilyNotifier.markKnown(meal.id)
            checkMilestone()
        }
        WidgetPublisher.publish(store: self)

        // Placing the meal in the family zone is a network round trip; don't
        // make the cook wait on it. reconcileSharing() retries anything missed.
        if role != .solo {
            let objectID = meal.objectID
            Task { await addToFamilyShare(objectID) }
        }
        return meal
    }

    func delete(_ meal: Meal) {
        if let id = meal.id {
            for rating in ratings(for: id) { context.delete(rating) }
        }
        context.delete(meal)
        saveQuietly()
        WidgetPublisher.publish(store: self)
    }

    func canEdit(_ meal: Meal) -> Bool {
        guard persistence.isCloudBacked, !meal.isDeleted else { return !meal.isDeleted }
        return persistence.container.canUpdateRecord(forManagedObjectWith: meal.objectID)
    }

    func canDelete(_ meal: Meal) -> Bool {
        guard persistence.isCloudBacked, !meal.isDeleted else { return !meal.isDeleted }
        return persistence.container.canDeleteRecord(forManagedObjectWith: meal.objectID)
    }

    /// New meals go where the whole family can see them.
    private var storeForNewFamilyObjects: NSPersistentStore? {
        role == .participant ? (persistence.sharedStore ?? persistence.privateStore) : persistence.privateStore
    }

    private func checkMilestone() {
        let request = NSFetchRequest<Meal>(entityName: "Meal")
        guard let count = try? context.count(for: request) else { return }
        milestone = SundayCalendar.milestoneMessage(forDinnerCount: count)
    }

    // MARK: Private ratings

    /// All of your ratings for a meal, newest first. Normally one, but two
    /// devices rating offline can produce duplicates (CloudKit has no unique
    /// constraints), so callers always take the first.
    private func ratings(for mealID: UUID) -> [Rating] {
        let request = NSFetchRequest<Rating>(entityName: "Rating")
        request.predicate = NSPredicate(format: "mealID == %@", mealID as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Rating.updatedAt, ascending: false)]
        if let privateStore = persistence.privateStore { request.affectedStores = [privateStore] }
        return (try? context.fetch(request)) ?? []
    }

    func stars(for meal: Meal) -> Int {
        guard let id = meal.id else { return 0 }
        return Int(ratings(for: id).first?.stars ?? 0)
    }

    func setRating(_ stars: Int, for meal: Meal) {
        guard !meal.isDeleted, meal.managedObjectContext != nil else { return }
        setRatingWithoutSaving(stars, mealID: meal.id)
        saveQuietly()
    }

    private func setRatingWithoutSaving(_ stars: Int, mealID: UUID?) {
        guard let mealID else { return }
        var existing = ratings(for: mealID)
        let keep = existing.isEmpty ? nil : existing.removeFirst()
        for duplicate in existing { context.delete(duplicate) } // collapse duplicates

        if stars <= 0 {
            if let keep { context.delete(keep) }
            return
        }
        let rating = keep ?? Rating(context: context)
        if keep == nil {
            rating.id = UUID()
            rating.mealID = mealID
            // Ratings never leave your own iCloud.
            if let privateStore = persistence.privateStore { context.assign(rating, to: privateStore) }
        }
        rating.stars = Int16(min(stars, 5))
        rating.updatedAt = .now
    }

    // MARK: Suggestions

    /// Joins meals with your ratings. Ratings are passed newest first (as the
    /// views fetch them), so duplicates resolve to the most recent.
    func summaries(meals: [Meal], ratings: [Rating]) -> [MealSummary] {
        let starsByMeal = Self.starsByMeal(ratings)
        return meals.compactMap { meal in
            guard let id = meal.id, let date = meal.date else { return nil }
            return MealSummary(id: id, name: meal.displayName, date: date, stars: starsByMeal[id])
        }
    }

    static func starsByMeal<S: Sequence>(_ ratings: S) -> [UUID: Int] where S.Element == Rating {
        Dictionary(ratings.compactMap { r in r.mealID.map { ($0, Int(r.stars)) } }, uniquingKeysWith: { first, _ in first })
    }

    func meal(withID id: UUID) -> Meal? {
        let request = NSFetchRequest<Meal>(entityName: "Meal")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    // MARK: Family sharing

    func refreshShare() {
        guard persistence.isCloudBacked else { return }
        do {
            // If you both own a family and joined one, the one you own wins.
            let newShare: CKShare?
            let newRole: FamilyRole
            if let store = persistence.privateStore, let owned = try persistence.container.fetchShares(in: store).first {
                (newShare, newRole) = (owned, .owner)
            } else if let store = persistence.sharedStore, let joined = try persistence.container.fetchShares(in: store).first {
                (newShare, newRole) = (joined, .participant)
            } else {
                (newShare, newRole) = (nil, .solo)
            }
            // Only publish real changes; this runs on every remote change.
            if newRole != role { role = newRole }
            if newShare?.recordID != share?.recordID
                || newShare?.participants.count != share?.participants.count
                || newShare?.modificationDate != share?.modificationDate {
                share = newShare
            }
        } catch {
            logger.error("fetchShares failed: \(error.localizedDescription)")
        }
    }

    func refreshAccountStatus() async {
        guard persistence.isCloudBacked else { return }
        do {
            accountStatus = try await persistence.ckContainer.accountStatus()
        } catch {
            accountStatus = .couldNotDetermine
        }
    }

    /// Returns the family share, creating it (and moving your dinners into it) on first use.
    func familyShare() async throws -> CKShare {
        refreshShare()
        if let share { return share }
        guard hasCompletedFirstImport else {
            throw SharingError.stillSyncing
        }
        guard let privateStore = persistence.privateStore else { throw CKError(.notAuthenticated) }

        // Reuse a Family left over from an earlier attempt or a stopped share.
        let familyRequest = NSFetchRequest<Family>(entityName: "Family")
        familyRequest.affectedStores = [privateStore]
        familyRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Family.createdAt, ascending: true)]
        let family: Family
        if let existing = try context.fetch(familyRequest).first {
            family = existing
        } else {
            family = Family(context: context)
            family.id = UUID()
            family.name = "Sunday Dinners"
            family.createdAt = .now
            context.assign(family, to: privateStore)
            try context.save()
        }

        let request = NSFetchRequest<Meal>(entityName: "Meal")
        request.affectedStores = [privateStore]
        let meals = try context.fetch(request)

        let (_, newShare, _) = try await persistence.container.share([family] + (meals as [NSManagedObject]), to: nil)
        newShare[CKShare.SystemFieldKey.title] = "Sunday Dinners"
        newShare.publicPermission = .none
        let saved = try await persistence.container.persistUpdatedShare(newShare, in: privateStore)
        share = saved
        role = .owner
        return saved
    }

    func acceptShare(_ metadata: CKShare.Metadata) async {
        guard let sharedStore = persistence.sharedStore else { return }
        do {
            _ = try await persistence.container.acceptShareInvitations(from: [metadata], into: sharedStore)
            refreshShare()
        } catch {
            logger.error("Accepting share failed: \(error.localizedDescription)")
        }
    }

    /// Moves a meal (and its photos) into the family zone if it isn't there yet.
    private func addToFamilyShare(_ objectID: NSManagedObjectID) async {
        guard let share, let meal = try? context.existingObject(with: objectID) as? Meal, !meal.isGone,
              sharingInFlight.insert(objectID).inserted
        else { return }
        defer { sharingInFlight.remove(objectID) }
        do {
            if let current = try persistence.container.fetchShares(matching: [objectID])[objectID],
               current.recordID == share.recordID {
                // Already in the zone. New photos follow their meal's zone; push
                // them explicitly only if any are still outside it.
                let photoIDs = meal.sortedPhotos.map(\.objectID)
                let photoShares = try persistence.container.fetchShares(matching: photoIDs)
                guard photoIDs.contains(where: { photoShares[$0] == nil }) else { return }
            }
            _ = try await persistence.container.share([meal], to: share)
        } catch {
            logger.error("Adding meal to family share failed (will retry): \(error.localizedDescription)")
        }
    }

    /// Catches up anything that should be shared but isn't (offline saves,
    /// the app killed mid-share), and tidies private ratings.
    func reconcile() {
        guard persistence.isCloudBacked, hasCompletedFirstImport else { return }
        reconcileTask?.cancel()
        reconcileTask = Task { [weak self] in
            // Imports arrive in bursts; settle before doing the work.
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.refreshShare()
            if self.role == .owner, let privateStore = self.persistence.privateStore {
                let request = NSFetchRequest<Meal>(entityName: "Meal")
                request.affectedStores = [privateStore]
                let meals = (try? self.context.fetch(request)) ?? []
                let shares = (try? self.persistence.container.fetchShares(matching: meals.map(\.objectID))) ?? [:]
                for meal in meals where shares[meal.objectID] == nil {
                    if Task.isCancelled { return }
                    await self.addToFamilyShare(meal.objectID)
                }
            }
            self.cleanUpRatings()
            WidgetPublisher.publish(store: self)
        }
    }

    /// Collapses duplicate ratings, and removes ratings for dinners someone
    /// else deleted. A rating whose dinner is missing might just be ahead of a
    /// slow import, so it's only deleted after a long grace period.
    private func cleanUpRatings() {
        guard let privateStore = persistence.privateStore, haveImportedAllStores else { return }
        let ratingRequest = NSFetchRequest<Rating>(entityName: "Rating")
        ratingRequest.affectedStores = [privateStore]
        ratingRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Rating.updatedAt, ascending: false)]
        guard let allRatings = try? context.fetch(ratingRequest), !allRatings.isEmpty else { return }

        let mealRequest = NSFetchRequest<NSDictionary>(entityName: "Meal")
        mealRequest.resultType = .dictionaryResultType
        mealRequest.propertiesToFetch = ["id"]
        let mealIDs = Set(((try? context.fetch(mealRequest)) ?? []).compactMap { $0["id"] as? UUID })

        let now = Date.now
        let previouslyOrphaned = UserDefaults.standard.dictionary(forKey: Self.orphanedRatingsKey) as? [String: Double] ?? [:]
        var orphaned: [String: Double] = [:]
        var seen = Set<UUID>()
        for rating in allRatings {
            guard let mealID = rating.mealID else {
                context.delete(rating)
                continue
            }
            if !seen.insert(mealID).inserted {
                context.delete(rating) // older duplicate
                continue
            }
            if !mealIDs.contains(mealID), let key = rating.id?.uuidString {
                let firstSeen = previouslyOrphaned[key] ?? now.timeIntervalSince1970
                if now.timeIntervalSince1970 - firstSeen > Self.orphanGracePeriod {
                    context.delete(rating)
                } else {
                    orphaned[key] = firstSeen
                }
            }
        }
        UserDefaults.standard.set(orphaned, forKey: Self.orphanedRatingsKey)
        saveQuietly()
    }

    private func observeCloudKit() {
        guard persistence.isCloudBacked else { return }
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: persistence.container,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.type == .import, event.endDate != nil, event.succeeded
            else { return }
            let storeIdentifier = event.storeIdentifier
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.importedStoreIdentifiers.contains(storeIdentifier) {
                    self.importedStoreIdentifiers.insert(storeIdentifier)
                }
                if !self.hasCompletedFirstImport {
                    if self.haveImportedAllStores {
                        self.hasCompletedFirstImport = true
                    } else if storeIdentifier == self.persistence.privateStore?.identifier {
                        self.startSharedImportFallback()
                    }
                }
                if self.persistence.isCloudBacked { FamilyNotifier.checkForNewDinners(store: self) }
                self.reconcile()
            }
        })

        observers.append(center.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshShare() }
        })
    }

    /// If you've never joined a family, the shared store may have nothing to
    /// import and never report one. Once the private store has imported, give
    /// the shared store a minute, then stop waiting for it.
    private func startSharedImportFallback() {
        guard sharedImportFallback == nil else { return }
        sharedImportFallback = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self, !Task.isCancelled, !self.hasCompletedFirstImport else { return }
            if let shared = self.persistence.sharedStore?.identifier {
                self.importedStoreIdentifiers.insert(shared)
            }
            self.hasCompletedFirstImport = true
            self.reconcile()
        }
    }

    // MARK: Helpers

    private func saveQuietly() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("Save failed: \(error.localizedDescription)")
            context.rollback()
        }
    }
}

enum SaveError: LocalizedError {
    case deletedElsewhere

    var errorDescription: String? {
        "Someone in the family deleted this dinner while you were editing it."
    }
}

enum SharingError: LocalizedError {
    case stillSyncing

    var errorDescription: String? {
        switch self {
        case .stillSyncing:
            "Sunday is still syncing with iCloud. Give it a minute, then try again so we don't create a second family."
        }
    }
}
