//
//  ServicesHomeManager.swift
//  Home Maintainer
//

import Foundation
import SwiftData
import CoreData

@Observable
final class HomeManager {
    var currentHome: Home?

    private let selectedHomeKey = "selectedHomeID"

    // MARK: - Selection

    func restoreSelection(from homes: [Home]) {
        let savedID = UserDefaults.standard.string(forKey: selectedHomeKey).flatMap { UUID(uuidString: $0) }
        if let id = savedID, let match = homes.first(where: { $0.id == id }) {
            currentHome = match
        } else if let first = homes.first {
            currentHome = first
            UserDefaults.standard.set(first.id.uuidString, forKey: selectedHomeKey)
        }
    }

    func select(_ home: Home) {
        currentHome = home
        UserDefaults.standard.set(home.id.uuidString, forKey: selectedHomeKey)
    }

    func clearSelection() {
        currentHome = nil
        UserDefaults.standard.removeObject(forKey: selectedHomeKey)
    }

    // MARK: - Owner detection

    /// Returns true if the current user owns this home. A home in the CloudKit shared store
    /// was created by someone else and shared to this device; a home in the private store
    /// belongs to this user.
    func isCurrentUserOwner(of home: Home) -> Bool {
        guard let service = CloudSharingService.shared,
              let sharedStore = service.sharedPersistentStore,
              let container = service.persistentCloudKitContainer else {
            return home.isLocallyCreated
        }
        let request = NSFetchRequest<NSManagedObject>(entityName: "Home")
        request.predicate = NSPredicate(format: "id == %@", home.id as NSUUID)
        request.fetchLimit = 1
        request.affectedStores = [sharedStore]
        let inSharedStore = (try? container.viewContext.fetch(request).first) != nil
        return !inSharedStore
    }

    // MARK: - File-open import coordination

    /// Set when the app is opened via a .homemaintainer file tap.
    /// Observed by ContentView to present the import confirmation sheet.
    var pendingImportURL: URL?
}
