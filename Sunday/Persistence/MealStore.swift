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
    var attendees: [String] = []
    var photos: [DraftPhoto] = []

    /// What the fields held when loaded from a saved dinner. Saving writes a
    /// field only if you changed it, so someone else's edit made while your
    /// editor was open isn't reverted by your stale copy.
    private(set) var original: (name: String, date: Date, cook: String, notes: String, attendees: [String])?
    /// Photos the dinner had when loaded. Only these can be deleted by a save;
    /// photos that synced in from someone else afterwards are left alone.
    private(set) var loadedPhotoIDs: Set<NSManagedObjectID> = []

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
        attendees = meal.tablePeople
        original = (name, date, cook, notes, attendees)
        loadedPhotoIDs = Set(meal.sortedPhotos.map(\.objectID))
    }

    /// Cheap equality for "are there unsaved changes?".
    var fingerprint: String {
        [name, cook, notes, "\(stars)", "\(date.timeIntervalSince1970)", attendees.joined(separator: ","), photos.map(\.id.uuidString).joined(separator: ",")]
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
    /// False from opening the app until the first iCloud import lands (or a
    /// short wait passes), so a phone opened late doesn't act on stale data.
    @Published private(set) var isFreshFromFamily = true
    private var freshnessTask: Task<Void, Never>?

    func didBecomeActive() {
        guard persistence.isCloudBacked, role != .solo else { return }
        isFreshFromFamily = false
        freshnessTask?.cancel()
        freshnessTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.isFreshFromFamily = true
        }
    }

    private static let importedStoresKey = "importedCloudKitStoreIdentifiers"
    private static let orphanedRatingsKey = "orphanedRatingsFirstSeen"
    /// How long a rating must point at a missing dinner before we delete it.
    private static let orphanGracePeriod: TimeInterval = 21 * 86_400
    private let logger = Logger(subsystem: "cooking.sunday.Sunday", category: "store")
    private var observers: [NSObjectProtocol] = []
    private var reconcileTask: Task<Void, Never>?
    private var sharingInFlight = Set<NSManagedObjectID>()
    private var sharedImportFallback: Task<Void, Never>?
    private var describeTask: Task<Void, Never>?
    /// A dinner was saved while a batch was running: look again after it.
    private var describeAgain = false
    /// Dinners whose photo the model looked at and found no food in.
    private static let notFoodKey = "describedNotFoodMealIDs"

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

        // Photo to tag after saving (on-device Vision), if the dinner has no tags yet.
        let photoToTag: Data? = (existing?.tags ?? "").isEmpty
            ? draft.photos.first(where: { $0.existing == nil }).flatMap { prepared[$0.id]?.full }
            : nil

        if let existing, existing.isGone { throw SaveError.deletedElsewhere }

        let isNew = existing == nil
        let meal = existing ?? Meal(context: context)
        let store = existing?.objectID.persistentStore ?? storeForNewFamilyObjects

        if isNew {
            meal.id = UUID()
            meal.createdAt = .now
            if let store { context.assign(meal, to: store) }
        }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cook = draft.cook.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = isNew ? nil : draft.original
        if original == nil || draft.name != original?.name { meal.name = name }
        if original == nil || draft.date != original?.date { meal.date = draft.date }
        if original == nil || draft.cook != original?.cook { meal.cook = cook }
        if original == nil || draft.notes != original?.notes { meal.notes = notes }
        if original == nil || draft.attendees != original?.attendees {
            meal.attendees = Attendance.encode(draft.attendees)
            // Unticking someone who checked in live takes their check-in too.
            for checkIn in meal.checkIns as? Set<CheckIn> ?? []
            where !draft.attendees.contains(where: { $0.caseInsensitiveCompare(checkIn.name ?? "") == .orderedSame }) {
                context.delete(checkIn)
            }
        }

        // Photos: drop the ones you removed, re-order kept ones, add new ones.
        // Photos someone else added after you opened the editor stay.
        let keptIDs = Set(draft.photos.compactMap { $0.existing?.objectID })
        for photo in meal.sortedPhotos
        where draft.loadedPhotoIDs.contains(photo.objectID) && !keptIDs.contains(photo.objectID) {
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
            photo.by = myName
            photo.imageData = images.full
            photo.thumbnailData = images.thumbnail
            if let store { context.assign(photo, to: store) }
            photo.meal = meal
        }

        setRatingWithoutSaving(draft.stars, mealID: meal.id)
        // A photo turns a plan into a dinner.
        if meal.isPlan, !draft.photos.isEmpty { meal.isPlan = false }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        if !meal.sortedPhotos.isEmpty {
            FamilyNotifier.markKnown(meal.id)
            if isNew || draft.photos.allSatisfy({ $0.existing == nil }) { checkMilestone() }
        }
        if let photoToTag { tagInBackground(meal.objectID, photo: photoToTag) }
        describeWaitingDinners()
        WidgetPublisher.publish(store: self)

        // Placing the meal in the family zone is a network round trip; don't
        // make the cook wait on it. reconcileSharing() retries anything missed.
        if role != .solo {
            let objectID = meal.objectID
            Task { await addToFamilyShare(objectID) }
        }
        if meal.isLive { LiveDinners.sync(store: self) }
        return meal
    }

    /// "Did you have Chili?" after a planned Sunday passes without a photo.
    func confirmPlan(_ meal: Meal, eaten: Bool) {
        guard !meal.isGone else { return }
        if eaten {
            meal.isPlan = false
            saveQuietly()
            FamilyNotifier.markKnown(meal.id)
        } else {
            delete(meal)
        }
    }

    func setRecipe(_ recipe: String, audio: Data?, by teller: String?, structure: StructuredRecipe? = nil, for meal: Meal) {
        guard !meal.isGone else { return }
        let trimmed = recipe.trimmingCharacters(in: .whitespacesAndNewlines)
        meal.recipe = trimmed.isEmpty ? nil : trimmed
        // Only while the text is still what the structure says.
        // The sorted card, or (after a typo fix) the text read back into one.
        let kept = structure.flatMap { $0.formatted == trimmed ? $0 : nil } ?? StructuredRecipe.parse(trimmed)
        meal.recipeStructure = kept?.encoded
        meal.recipeAudio = audio
        meal.recipeBy = teller
        saveQuietly()
    }

    /// A guest's story lives on the dinner itself, never on the dish recipe.
    func setStory(_ story: String, audio: Data?, by teller: String, for meal: Meal) {
        guard !meal.isGone else { return }
        let trimmed = story.trimmingCharacters(in: .whitespacesAndNewlines)
        meal.story = trimmed.isEmpty ? nil : trimmed
        meal.storyAudio = audio
        meal.storyBy = teller
        saveQuietly()
    }

    /// Ratings tapped on a widget, saved as your private ratings.
    func applyWidgetRatings() {
        guard !PersistenceController.isUITesting else { return }
        var applied = false
        PendingRatings.drain { entry in
            guard let meal = meal(withID: entry.mealID) else { return }
            setRating(entry.stars, for: meal)
            applied = true
        }
        if applied { WidgetPublisher.publish(store: self) }
    }

    /// "Who's cooking?" from the Tonight card.
    func setCook(_ cook: String?, for meal: Meal) {
        guard !meal.isGone else { return }
        meal.cook = cook
        saveQuietly()
    }

    // MARK: Sunday Live

    static let myNameKey = "myName"

    /// Who this phone belongs to at the table, in the family's own words
    /// ("Dad", not the iCloud name): asked once per phone, "Which one are you?"
    var myName: String? {
        guard let stored = UserDefaults.standard.string(forKey: Self.myNameKey), !stored.isEmpty else { return nil }
        return stored
    }

    func setMyName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(trimmed, forKey: Self.myNameKey)
        objectWillChange.send()
        recordMember(as: trimmed)
        applyPendingCheckIns()
        LiveDinners.sync(store: self)
    }

    /// "That's not me": forget this phone's name, and take back a live
    /// check-in made under it.
    func clearMyName() {
        if let me = myName, let live = liveMeal() { removeFromTable(me, meal: live) }
        UserDefaults.standard.removeObject(forKey: Self.myNameKey)
        objectWillChange.send()
        LiveDinners.sync(store: self)
    }

    // MARK: Members (iCloud account → family name)

    /// "Mom's family" for whoever owns the share, in family words.
    var ownerFamilyName: String? {
        guard let owner = share?.owner else { return nil }
        return memberName(for: owner)
    }

    /// Names other phones have already claimed, so two phones aren't both "Mom".
    var namesClaimedElsewhere: Set<String> {
        let mine = share?.currentUserParticipant.flatMap { participantKey($0) }
        return Set(members.filter { $0.participantID != mine }.compactMap { $0.name?.lowercased() })
    }

    /// The share's owner reads their own record name as a placeholder, so
    /// the owner is keyed by role instead.
    private func participantKey(_ participant: CKShare.Participant) -> String? {
        if participant.role == .owner { return "owner" }
        guard let recordName = participant.userIdentity.userRecordID?.recordName,
              recordName != CKCurrentUserDefaultName else { return nil }
        return recordName
    }

    private var members: [Member] {
        (try? context.fetch(NSFetchRequest<Member>(entityName: "Member"))) ?? []
    }

    /// The family's name for a share participant, if they've said.
    private func memberName(for participant: CKShare.Participant) -> String? {
        guard let key = participantKey(participant) else { return nil }
        return members.filter { $0.participantID == key }
            .max { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) }?.name
    }

    /// Tell the family which account this name is (shared, in the family zone).
    private func recordMember(as name: String) {
        guard role != .solo, !name.isEmpty, let me = share?.currentUserParticipant, let key = participantKey(me) else { return }
        let existing = members.first { $0.participantID == key }
        let member = existing ?? Member(context: context)
        if existing == nil {
            member.id = UUID()
            member.participantID = key
            if let store = storeForNewFamilyObjects { context.assign(member, to: store) }
        }
        guard member.name != name || existing == nil else { return }
        member.name = name
        member.updatedAt = .now
        saveQuietly()
        if let share {
            let objectID = member.objectID
            Task {
                guard let object = try? context.existingObject(with: objectID) else { return }
                _ = try? await persistence.container.share([object], to: share)
            }
        }
    }

    /// The dinner happening right now, if someone started it.
    func liveMeal() -> Meal? {
        let request = NSFetchRequest<Meal>(entityName: "Meal")
        request.predicate = NSPredicate(format: "liveAt != nil AND liveEndedAt == nil")
        // The first one started, if two phones somehow both did.
        return ((try? context.fetch(request)) ?? []).filter(\.isLive)
            .min { ($0.liveAt ?? .distantFuture) < ($1.liveAt ?? .distantFuture) }
    }

    /// "We're sitting down": the dinner goes live for the whole family.
    func startLive(_ meal: Meal) {
        guard !meal.isGone else { return }
        // Someone already sat down (maybe on a phone that synced first):
        // first starter wins; this phone just joins.
        if meal.isLive {
            checkIn(meal)
            return
        }
        meal.liveAt = .now
        meal.liveEndedAt = nil
        meal.liveBy = myName
        saveQuietly()
        if myName != nil { checkIn(meal) }
        FamilyNotifier.markLiveKnown(meal.id)
        LiveDinners.sync(store: self)
    }

    /// Live without a plan: any Sunday evening, name it later (or never).
    func startLiveTonight() async throws {
        // Someone beat us to it: join theirs instead of starting a second.
        if let live = liveMeal() {
            checkIn(live)
            return
        }
        var draft = MealDraft()
        draft.date = .now
        draft.cook = ""
        let meal = try await save(draft)
        meal.isPlan = true // Not history until a photo or "yes, we had it".
        saveQuietly()
        startLive(meal)
    }

    func rename(_ meal: Meal, to name: String) {
        guard !meal.isGone else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != meal.name else { return }
        meal.name = trimmed
        saveQuietly()
        LiveDinners.sync(store: self)
    }

    /// "I'm here": its own record in the dinner's zone, so four phones
    /// tapping at once all count.
    func checkIn(_ meal: Meal, as name: String? = nil, at time: Date = .now) {
        guard !meal.isGone, meal.isLive, let name = name ?? myName,
              !meal.tablePeople.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
        else { return }
        let record = CheckIn(context: context)
        record.id = UUID()
        record.name = name
        record.at = time
        if let store = meal.objectID.persistentStore { context.assign(record, to: store) }
        record.meal = meal
        saveQuietly()
        if role == .owner {
            let objectID = meal.objectID
            Task { await addToFamilyShare(objectID) }
        }
        LiveDinners.sync(store: self)
    }

    func isCheckedIn(_ meal: Meal) -> Bool {
        guard let me = myName else { return false }
        return meal.tablePeople.contains { $0.caseInsensitiveCompare(me) == .orderedSame }
    }

    /// Only whoever started dinner, or the cook, wraps it up for everyone.
    func canEndLive(_ meal: Meal) -> Bool {
        guard let me = myName else { return meal.liveBy == nil }
        return [meal.liveBy, meal.cook].contains { ($0 ?? "").caseInsensitiveCompare(me) == .orderedSame }
            || meal.liveBy == nil
    }

    /// "That's dinner": the evening is over; check-ins become the record and
    /// rating takes it from here.
    func endLive(_ meal: Meal) {
        guard !meal.isGone else { return }
        settle(meal, endedAt: .now)
        saveQuietly()
        WidgetPublisher.publish(store: self)
        LiveDinners.sync(store: self)
    }

    /// Check-ins become who was at the table; an evening people checked in
    /// to happened, photo or not (never "Did you have it?" the next day).
    private func settle(_ meal: Meal, endedAt: Date) {
        meal.attendees = Attendance.encode(meal.tablePeople)
        meal.liveEndedAt = endedAt
        if meal.isPlan, !meal.tablePeople.isEmpty { meal.isPlan = false }
    }

    /// Live dinners nobody wrapped up, whose evening has passed.
    func settleFinishedLive() {
        let request = NSFetchRequest<Meal>(entityName: "Meal")
        request.predicate = NSPredicate(format: "liveAt != nil AND liveEndedAt == nil")
        let finished = ((try? context.fetch(request)) ?? []).filter { !$0.isLive }
        guard !finished.isEmpty else { return }
        for meal in finished {
            settle(meal, endedAt: meal.liveAt.map { LiveDinner.endsAt($0) } ?? .now)
        }
        saveQuietly()
        LiveDinners.sync(store: self)
    }

    /// "Not here": a face on the Live card that shouldn't be.
    func removeFromTable(_ name: String, meal: Meal) {
        guard !meal.isGone else { return }
        for checkIn in meal.checkIns as? Set<CheckIn> ?? []
        where (checkIn.name ?? "").caseInsensitiveCompare(name) == .orderedSame {
            context.delete(checkIn)
        }
        meal.attendees = Attendance.encode(Attendance.decode(meal.attendees).filter { $0.caseInsensitiveCompare(name) != .orderedSame })
        saveQuietly()
        LiveDinners.sync(store: self)
    }

    /// Snap at the table: the photo goes straight onto the live dinner.
    /// No form, no stars; rating comes after.
    @discardableResult
    func addLivePhoto(_ image: UIImage, to meal: Meal) async -> Photo? {
        let images = await ImageProcessing.prepareAsync(image)
        guard !meal.isGone, let images else { return nil }
        let photo = Photo(context: context)
        photo.id = UUID()
        photo.createdAt = .now
        photo.sortIndex = Int16(meal.sortedPhotos.count)
        photo.by = myName
        photo.imageData = images.full
        photo.thumbnailData = images.thumbnail
        if let store = meal.objectID.persistentStore { context.assign(photo, to: store) }
        photo.meal = meal
        if meal.isPlan { meal.isPlan = false }
        saveQuietly()
        FamilyNotifier.markKnown(meal.id)
        WidgetPublisher.publish(store: self)
        if role == .owner {
            let objectID = meal.objectID
            Task { await addToFamilyShare(objectID) }
        }
        LiveDinners.sync(store: self)
        return photo
    }

    func deletePhoto(_ photo: Photo) {
        context.delete(photo)
        saveQuietly()
        LiveDinners.sync(store: self)
    }


    /// Check-ins tapped on a Live Activity or notification. Waits for a
    /// name: the app asks "Which one are you?" when one is queued.
    func applyPendingCheckIns() {
        guard !PersistenceController.isUITesting, myName != nil else { return }
        PendingCheckIns.drain { entry in
            // Not synced here yet: keep it. Over already: drop it.
            guard let meal = meal(withID: entry.mealID) else { return false }
            if meal.isLive { checkIn(meal, at: entry.at) }
            return true
        }
    }

    /// A check-in is waiting on "Which one are you?"
    var needsMyName: Bool {
        myName == nil && !PendingCheckIns.read().isEmpty
    }

    /// Plan a dinner for this Sunday (or today, if it's Sunday): a dinner
    /// with a name and no photo yet. Snapping it later joins this dinner.
    @discardableResult
    func planSunday(_ name: String) async throws -> Meal {
        let calendar = Calendar.current
        let sunday = SundayCalendar.upcomingSunday(onOrAfter: .now)
        if let existing = (try? context.fetch(NSFetchRequest<Meal>(entityName: "Meal")))?.first(where: {
            $0.date.map { calendar.isDate($0, inSameDayAs: sunday) } ?? false
        }), existing.sortedPhotos.isEmpty {
            existing.name = name
            saveQuietly()
            return existing
        }
        var draft = MealDraft()
        draft.name = name
        draft.date = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: sunday) ?? sunday
        let plan = try await save(draft)
        plan.isPlan = true
        saveQuietly()
        return plan
    }

    /// Vision takes up to a second; don't make the cook wait for it.
    private func tagInBackground(_ objectID: NSManagedObjectID, photo: Data) {
        Task {
            let tags = await FoodTagger.tags(forJPEG: photo)
            guard !tags.isEmpty, let meal = try? context.existingObject(with: objectID) as? Meal,
                  !meal.isGone, (meal.tags ?? "").isEmpty
            else { return }
            meal.tags = FoodTags.encode(tags)
            saveQuietly()
        }
    }

    /// Writes the one-line caption for dinners that have a photo but no
    /// caption yet: tonight's, and every older one posted before a phone in
    /// the family could look at photos. Newest first, a batch per visit, one
    /// at a time so the phone stays cool.
    func describeWaitingDinners() {
        guard !PersistenceController.isUITesting, MealDescriber.isAvailable else { return }
        guard describeTask == nil else {
            describeAgain = true
            return
        }
        describeTask = Task { [weak self] in
            guard let self else { return }
            defer {
                describeTask = nil
                if describeAgain, !Task.isCancelled {
                    describeAgain = false
                    describeWaitingDinners()
                }
            }
            var notFood = Set(UserDefaults.standard.stringArray(forKey: Self.notFoodKey) ?? [])
            let request = NSFetchRequest<Meal>(entityName: "Meal")
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Meal.date, ascending: false)]
            let waiting = ((try? context.fetch(request)) ?? []).filter { meal in
                guard let id = meal.id, !meal.isPlan, (meal.caption ?? "").isEmpty else { return false }
                return !notFood.contains(id.uuidString) && !meal.sortedPhotos.isEmpty && canEdit(meal)
            }
            for objectID in waiting.prefix(25).map(\.objectID) {
                guard !Task.isCancelled else { return }
                // A photo still downloading from iCloud waits for the next visit.
                guard let meal = try? context.existingObject(with: objectID) as? Meal, !meal.isGone,
                      let id = meal.id, let photo = meal.sortedPhotos.first?.imageData
                else { continue }
                switch await MealDescriber.describe(jpeg: photo) {
                case .described(let description):
                    // Someone else's phone may have got there while this one looked.
                    guard !meal.isGone, (meal.caption ?? "").isEmpty, !description.caption.isEmpty else { continue }
                    meal.caption = description.caption
                    saveQuietly()
                case .notFood:
                    notFood.insert(id.uuidString)
                    UserDefaults.standard.set(Array(notFood), forKey: Self.notFoodKey)
                case .failed:
                    continue
                }
            }
        }
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
            // Plans aren't history yet.
            guard !meal.isPlan, let id = meal.id, let date = meal.date else { return nil }
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

    /// Names of people in the family share (owner and accepted members).
    /// The family's own names ("Dad"), from Member records. Accounts that
    /// haven't said who they are stay out by default, so "Kirk" never shows
    /// up next to "Dad"; `mappedOnly: false` falls back to the iCloud name.
    func participantNames(mappedOnly: Bool = true) -> [String] {
        (share?.participants ?? []).compactMap { participant -> String? in
            guard participant.role == .owner || participant.acceptanceStatus == .accepted else { return nil }
            if let mapped = memberName(for: participant) { return mapped }
            guard !mappedOnly, let components = participant.userIdentity.nameComponents else { return nil }
            let name = components.formatted(.name(style: .short))
            return name.isEmpty ? nil : name
        }
    }

    var participantNames: [String] { participantNames() }

    /// Everyone we know of at this family's table: share members, cooks and
    /// past guests, most-seen first.
    func familyNames(from meals: [Meal], mappedOnly: Bool = true) -> [String] {
        var counts: [String: (name: String, count: Int)] = [:]
        for name in participantNames(mappedOnly: mappedOnly) { counts[name.lowercased(), default: (name, 0)].count += 1000 }
        for meal in meals {
            let people = meal.tablePeople + [meal.cook ?? ""]
            for person in people.map({ $0.trimmingCharacters(in: .whitespaces) }) where !person.isEmpty {
                counts[person.lowercased(), default: (person, 0)].count += 1
            }
        }
        return counts.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }.map(\.name)
    }

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
        if let me = myName { recordMember(as: me) }
        if FamilyNotifier.isEnabled { _ = await Reminders.requestAuthorization() }
        return saved
    }

    func acceptShare(_ metadata: CKShare.Metadata) async {
        guard let sharedStore = persistence.sharedStore else { return }
        do {
            _ = try await persistence.container.acceptShareInvitations(from: [metadata], into: sharedStore)
            refreshShare()
            if let me = myName { recordMember(as: me) }
            if FamilyNotifier.isEnabled { _ = await Reminders.requestAuthorization() }
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
                    + (meal.checkIns as? Set<CheckIn> ?? []).map(\.objectID)
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
                // A participant's family lives in the shared store: wait for that one.
                let familyStore = self.role == .participant ? self.persistence.sharedStore?.identifier : nil
                if !self.isFreshFromFamily, familyStore == nil || storeIdentifier == familyStore {
                    self.isFreshFromFamily = true
                    self.freshnessTask?.cancel()
                }
                if self.persistence.isCloudBacked {
                    FamilyNotifier.checkForNewDinners(store: self)
                    FamilyNotifier.checkForLiveDinner(store: self)
                }
                LiveDinners.sync(store: self)
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
