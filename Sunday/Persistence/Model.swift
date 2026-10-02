import CoreData

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
    @NSManaged var createdAt: Date?
    @NSManaged var photos: NSSet?

    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled dinner" : trimmed
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

        let meal = entity("Meal", [
            attribute("id", .UUIDAttributeType),
            attribute("name", .stringAttributeType),
            attribute("date", .dateAttributeType),
            attribute("cook", .stringAttributeType),
            attribute("notes", .stringAttributeType),
            attribute("createdAt", .dateAttributeType),
            mealPhotos,
        ])

        let photo = entity("Photo", [
            attribute("id", .UUIDAttributeType),
            attribute("imageData", .binaryDataAttributeType, externalStorage: true),
            attribute("thumbnailData", .binaryDataAttributeType, externalStorage: true),
            attribute("sortIndex", .integer16AttributeType, default: 0),
            attribute("createdAt", .dateAttributeType),
            photoMeal,
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

        let model = NSManagedObjectModel()
        model.entities = [meal, photo, rating, family]
        return model
    }
}
