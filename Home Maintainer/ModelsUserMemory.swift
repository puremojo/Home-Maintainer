//
//  ModelsUserMemory.swift
//  Home Maintainer
//
//  Replaces the Firestore `users/{uid}.aiMemory` field. Synced via CloudSharingService's
//  private "personal" CloudKit zone (never shared), with `content` stored using CKRecord's
//  encryptedValues so it's unreadable outside the user's own device/iCloud account.
//

import Foundation
import CoreData

@objc(UserMemory)
public final class UserMemory: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var content: String?
    @NSManaged public var updatedAt: Date

    /// There is exactly one UserMemory record per account. Fetches it, creating it on
    /// first use with a stable well-known id so re-imports from CloudKit always resolve
    /// to the same local row rather than duplicating it.
    static let wellKnownID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @discardableResult
    static func fetchOrCreate(in context: NSManagedObjectContext) -> UserMemory {
        let fetch = NSFetchRequest<UserMemory>(entityName: "UserMemory")
        fetch.predicate = NSPredicate(format: "id == %@", wellKnownID as NSUUID)
        fetch.fetchLimit = 1
        if let existing = (try? context.fetch(fetch))?.first {
            return existing
        }
        let memory = UserMemory(context: context)
        memory.id = wellKnownID
        memory.content = nil
        memory.updatedAt = Date()
        return memory
    }
}
