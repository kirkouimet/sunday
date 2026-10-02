import CoreData
import SundayKit

// The Core Data model is defined in code so it lives in plain, reviewable Swift.
// CloudKit rules apply: every attribute is optional or defaulted, every
// relationship is optional with an inverse, and there are no unique constraints.

@objc(Meal)
final class Meal: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var date: Date?
    @NSManaged var cook: String?
    @NSManaged var notes: String?
    /// On-device food tags from the first photo, e.g. "pasta,salad".
    @NSManaged var tags: String?
    /// Who was at the table: "Mom,Dad,Grandma June".
    @NSManaged var attendees: String?
    /// The family's own way of making this dish, if someone wrote it down.
    @NSManaged var recipe: String?
    /// Planned ahead ("Make it Sunday") and not yet confirmed as eaten.
    /// Plans don't count as history until a photo or a "yes, we had it".
    @NSManaged var isPlan: Bool
    /// The cook telling the recipe in their own voice (AAC).
    @NSManaged var recipeAudio: Data?
    /// The recipe sorted into ingredients and steps (StructuredRecipe JSON).
    @NSManaged var recipeStructure: String?
    /// Who told the recipe (defaults to the cook).
    @NSManaged var recipeBy: String?
    /// A guest's own story from this dinner ("Grandma June: how I make
    /// pierogi"), kept apart from the dish's recipe so it never overwrites it.
    @NSManaged var story: String?
    @NSManaged var storyAudio: Data?
    @NSManaged var storyBy: String?
    /// Sunday Live: when someone tapped "We're sitting down", who did, and
    /// when the evening was wrapped up. Live dinners take check-ins and
    /// everyone's photos.
    @NSManaged var liveAt: Date?
    @NSManaged var liveBy: String?
    @NSManaged var liveEndedAt: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var photos: NSSet?
    /// "I'm here" taps during Sunday Live, one record each, so phones
    /// checking in at the same moment never overwrite each other.
    @NSManaged var checkIns: NSSet?

    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Sunday dinner" : trimmed
    }

    var isLive: Bool { LiveDinner.isLive(startedAt: liveAt, endedAt: liveEndedAt) }

    /// Everyone at the table: who was recorded, plus who checked in live.
    var tablePeople: [String] {
        let checkedIn = (checkIns as? Set<CheckIn> ?? [])
            .sorted { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) }
            .compactMap(\.name)
        return Attendance.decode(Attendance.encode(Attendance.decode(attendees) + checkedIn))
    }

    var sortedPhotos: [Photo] {
        (photos as? Set<Photo> ?? []).sorted {
            if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
            return ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
    }
}

@objc(Photo)
final class Photo: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var imageData: Data?
    @NSManaged var thumbnailData: Data?
    @NSManaged var sortIndex: Int16
    @NSManaged var createdAt: Date?
    /// Who took it (on Sunday Live, everyone's a photographer).
    @NSManaged var by: String?
    @NSManaged var meal: Meal?
}

/// One person saying "I'm here" at a live dinner. Lives in the dinner's
/// zone like a photo; never edited, so it can't conflict.
@objc(CheckIn)
final class CheckIn: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var at: Date?
    @NSManaged var meal: Meal?
}

/// A person's private star rating. Lives only in that person's private iCloud
/// database and is never shared, so it references its meal by UUID instead of
/// a relationship (meals may live in a different store).
@objc(Rating)
final class Rating: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var mealID: UUID?
    @NSManaged var stars: Int16
    @NSManaged var updatedAt: Date?
}

/// The root object the family share is created from. One per family.
@objc(Family)
final class Family: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
}

enum SundayModel {
    static let shared: NSManagedObjectModel = make()

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        default defaultValue: Any? = nil,
        externalStorage: Bool = false
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = true
        attribute.defaultValue = defaultValue
        attribute.allowsExternalBinaryDataStorage = externalStorage
        return attribute
    }

    private static func entity(_ name: String, _ properties: [NSPropertyDescription]) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = name
        entity.managedObjectClassName = name
        entity.properties = properties
        return entity
    }

    private static func make() -> NSManagedObjectModel {
        let mealPhotos = NSRelationshipDescription()
        mealPhotos.name = "photos"
        mealPhotos.isOptional = true
        mealPhotos.minCount = 0
        mealPhotos.maxCount = 0 // to-many
        mealPhotos.deleteRule = .cascadeDeleteRule

        let photoMeal = NSRelationshipDescription()
        photoMeal.name = "meal"
        photoMeal.isOptional = true
        photoMeal.minCount = 0
        photoMeal.maxCount = 1
        photoMeal.deleteRule = .nullifyDeleteRule

        let mealCheckIns = NSRelationshipDescription()
        mealCheckIns.name = "checkIns"
        mealCheckIns.isOptional = true
        mealCheckIns.minCount = 0
        mealCheckIns.maxCount = 0
        mealCheckIns.deleteRule = .cascadeDeleteRule

        let checkInMeal = NSRelationshipDescription()
        checkInMeal.name = "meal"
        checkInMeal.isOptional = true
        checkInMeal.minCount = 0
        checkInMeal.maxCount = 1
        checkInMeal.deleteRule = .nullifyDeleteRule

        let meal = entity("Meal", [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("date", .dateAttributeType),
            attribute("cook", .stringAttributeType),
            attribute("notes", .stringAttributeType),
            attribute("tags", .stringAttributeType),
            attribute("attendees", .stringAttributeType),
            attribute("recipe", .stringAttributeType),
            attribute("isPlan", .booleanAttributeType, default: false),
            attribute("recipeAudio", .binaryDataAttributeType, externalStorage: true),
            attribute("recipeBy", .stringAttributeType),
            attribute("recipeStructure", .stringAttributeType),
            attribute("story", .stringAttributeType),
            attribute("storyAudio", .binaryDataAttributeType, externalStorage: true),
            attribute("storyBy", .stringAttributeType),
            attribute("liveAt", .dateAttributeType),
            attribute("liveBy", .stringAttributeType),
            attribute("liveEndedAt", .dateAttributeType),
            attribute("createdAt", .dateAttributeType),
            mealPhotos,
            mealCheckIns,
        ])

        let photo = entity("Photo", [
            attribute("id", .UUIDAttributeType),
            attribute("imageData", .binaryDataAttributeType, externalStorage: true),
            attribute("thumbnailData", .binaryDataAttributeType, externalStorage: true),
            attribute("sortIndex", .integer16AttributeType, default: 0),
            attribute("createdAt", .dateAttributeType),
            attribute("by", .stringAttributeType),
            photoMeal,
        ])

        let checkIn = entity("CheckIn", [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("at", .dateAttributeType),
            checkInMeal,
        ])

        let rating = entity("Rating", [
            attribute("id", .UUIDAttributeType),
            attribute("mealID", .UUIDAttributeType),
            attribute("stars", .integer16AttributeType, default: 0),
            attribute("updatedAt", .dateAttributeType),
        ])

        let family = entity("Family", [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
        ])

        mealPhotos.destinationEntity = photo
        mealPhotos.inverseRelationship = photoMeal
        photoMeal.destinationEntity = meal
        photoMeal.inverseRelationship = mealPhotos
        mealCheckIns.destinationEntity = checkIn
        mealCheckIns.inverseRelationship = checkInMeal
        checkInMeal.destinationEntity = meal
        checkInMeal.inverseRelationship = mealCheckIns

        let model = NSManagedObjectModel()
        model.entities = [meal, photo, rating, family, checkIn]
        return model
    }
}
