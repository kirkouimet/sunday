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
        photos = meal.sortedPhotos.compactMap { photo in
            guard let data = photo.thumbnailData ?? photo.imageData, let image = UIImage(data: data) else { return nil }
            return DraftPhoto(image: image, existing: photo)
        }
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

    private let logger = Logger(subsystem: "com.kirkouimet.sunday", category: "store")

    init(persistence: PersistenceController) {
        self.persistence = persistence
        refreshShare()
    }

    // MARK: Meals

    @discardableResult
    func save(_ draft: MealDraft, editing existing: Meal? = nil) async throws -> Meal {
        let meal = existing ?? Meal(context: context)
        let store = existing?.objectID.persistentStore ?? storeForNewFamilyObjects

        if existing == nil {
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
            guard let prepared = await ImageProcessing.prepareAsync(draftPhoto.image) else { continue }
            let photo = Photo(context: context)
            photo.id = UUID()
            photo.createdAt = .now
            photo.sortIndex = Int16(index)
            photo.imageData = prepared.full
            photo.thumbnailData = prepared.thumbnail
            if let store { context.assign(photo, to: store) }
            photo.meal = meal
        }

        setRatingWithoutSaving(draft.stars, mealID: meal.id)
        try context.save()

        // Owners keep the family's dinners in the share's zone so everyone sees them.
        if role == .owner, let share, meal.objectID.persistentStore == persistence.privateStore {
            do {
                _ = try await persistence.container.share([meal], to: share)
            } catch {
                logger.error("Adding meal to family share failed: \(error.localizedDescription)")
            }
        }
        return meal
    }

    func delete(_ meal: Meal) {
        if let id = meal.id, let rating = rating(for: id) {
            context.delete(rating)
        }
        context.delete(meal)
        saveQuietly()
    }

    func canEdit(_ meal: Meal) -> Bool {
        guard persistence.isCloudBacked else { return true }
        return persistence.container.canUpdateRecord(forManagedObjectWith: meal.objectID)
    }

    /// New meals go where the whole family can see them.
    private var storeForNewFamilyObjects: NSPersistentStore? {
        role == .participant ? (persistence.sharedStore ?? persistence.privateStore) : persistence.privateStore
    }

    // MARK: Private ratings

    func rating(for mealID: UUID) -> Rating? {
        let request = NSFetchRequest<Rating>(entityName: "Rating")
        request.predicate = NSPredicate(format: "mealID == %@", mealID as CVarArg)
        if let privateStore = persistence.privateStore { request.affectedStores = [privateStore] }
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    func stars(for meal: Meal) -> Int {
        guard let id = meal.id else { return 0 }
        return Int(rating(for: id)?.stars ?? 0)
    }

    func setRating(_ stars: Int, for meal: Meal) {
        setRatingWithoutSaving(stars, mealID: meal.id)
        saveQuietly()
    }

    private func setRatingWithoutSaving(_ stars: Int, mealID: UUID?) {
        guard let mealID else { return }
        let existing = rating(for: mealID)
        if stars <= 0 {
            if let existing { context.delete(existing) }
            return
        }
        let rating = existing ?? Rating(context: context)
        if existing == nil {
            rating.id = UUID()
            rating.mealID = mealID
            // Ratings never leave your own iCloud.
            if let privateStore = persistence.privateStore { context.assign(rating, to: privateStore) }
        }
        rating.stars = Int16(min(stars, 5))
        rating.updatedAt = .now
    }

    // MARK: Suggestions

    func summaries(meals: [Meal], ratings: [Rating]) -> [MealSummary] {
        let starsByMeal = Dictionary(ratings.compactMap { r in r.mealID.map { ($0, Int(r.stars)) } },
                                     uniquingKeysWith: { a, _ in a })
        return meals.compactMap { meal in
            guard let id = meal.id, let date = meal.date else { return nil }
            return MealSummary(id: id, name: meal.displayName, date: date, stars: starsByMeal[id])
        }
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
            if let store = persistence.privateStore, let owned = try persistence.container.fetchShares(in: store).first {
                share = owned
                role = .owner
            } else if let store = persistence.sharedStore, let joined = try persistence.container.fetchShares(in: store).first {
                share = joined
                role = .participant
            } else {
                share = nil
                role = .solo
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
        guard let privateStore = persistence.privateStore else { throw CKError(.notAuthenticated) }

        let family = Family(context: context)
        family.id = UUID()
        family.name = "Sunday Dinners"
        family.createdAt = .now
        context.assign(family, to: privateStore)
        try context.save()

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
