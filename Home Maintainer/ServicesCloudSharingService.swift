
//
//  ServicesCloudSharingService.swift
//  Home Maintainer
//
//  Manages CloudKit zone sharing for Home objects via NSPersistentCloudKitContainer.
//  The underlying container is captured lazily from the first CloudKit sync event
//  that SwiftData posts after the store loads.
//
//  Sharing architecture:
//  SwiftData only exposes a private CloudKit store, but NSPersistentCloudKitContainer
//  (which SwiftData uses internally) can also manage a shared store. Once we capture
//  the container we append a shared-database store description and call loadPersistentStores
//  again — it only loads descriptions that aren't already in the coordinator. SwiftData's
//  NSManagedObjectContext then sees records from both stores, so shared homes appear in
//  @Query automatically. acceptShareInvitations requires a .shared-scoped store; supplying
//  it correctly is what prevents the SIGABRT seen in earlier builds.
//

import Foundation
import SwiftUI
import SwiftData
import CoreData
import CloudKit
import UIKit

@Observable
final class CloudSharingService {

    // MARK: - Shared singleton (set at app startup so SceneDelegate can reach it)
    static var shared: CloudSharingService?

    // MARK: - State

    private(set) var persistentCloudKitContainer: NSPersistentCloudKitContainer?
    /// True after CloudKit completes a successful setup or export — required before share(_:to:) works reliably.
    private(set) var isCloudKitReady = false
    /// The shared-database store appended to SwiftData's container after first launch.
    private(set) var sharedPersistentStore: NSPersistentStore?
    /// True once the shared store is loaded and registered with the ModelContainer.
    /// ContentView observes this to run one-time owner-name fixups safely.
    private(set) var sharedStoreIsReady = false
    /// Non-nil when share acceptance fails. ContentView observes this to show an alert.
    var shareAcceptError: String?
    private var eventObserver: NSObjectProtocol?



    // MARK: - Init

    init() {
        // Capture the NSPersistentCloudKitContainer that SwiftData creates internally.
        // The container posts eventChangedNotification shortly after the store loads.
        eventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            // Capture container on first event and add the shared store.
            if self.persistentCloudKitContainer == nil,
               let container = notification.object as? NSPersistentCloudKitContainer {
                self.persistentCloudKitContainer = container
                self.setupDatabaseSubscriptions(container: container)
                self.setupSharedStore(container: container)
            }

            // Mark ready once a setup or export event succeeds — sharing requires this.
            if let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
               event.succeeded,
               event.type == .setup || event.type == .export {
                self.isCloudKitReady = true
                print("[CloudSharingService] CloudKit ready (event type: \(event.type))")
            }
        }
    }

    deinit {
        if let observer = eventObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Shared Store Setup

    private func setupSharedStore(container: NSPersistentCloudKitContainer) {
        let sharedStoreURL = sharedStoreFileURL

        // Already loaded (e.g. second notification firing after restart).
        if let existing = container.persistentStoreCoordinator.persistentStores
            .first(where: { $0.url == sharedStoreURL }) {
            sharedPersistentStore = existing
            sharedStoreIsReady = true
            print("[CloudSharingService] Shared store already present")
            return
        }

        let desc = NSPersistentStoreDescription(url: sharedStoreURL)
        let ckOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: "iCloud.EstraDOS.Home-Maintainer"
        )
        ckOptions.databaseScope = .shared
        desc.cloudKitContainerOptions = ckOptions

        // CloudKit's internal batch record import requires a clean context.
        // Pending changes at this point trigger "Illegal attempt to begin batch processing"
        // and can invalidate object references, causing downstream crashes.
        if container.viewContext.hasChanges {
            try? container.viewContext.save()
        }

        // Calling loadPersistentStores again only loads descriptions not yet in the
        // coordinator — existing stores are returned as-is without re-loading.
        container.persistentStoreDescriptions.append(desc)
        container.loadPersistentStores { [weak self] loadedDesc, error in
            guard let self else { return }
            if let error {
                print("[CloudSharingService] Shared store failed to load: \(error)")
                return
            }
            guard loadedDesc.url == sharedStoreURL else { return }
            DispatchQueue.main.async {
                self.sharedPersistentStore = container.persistentStoreCoordinator
                    .persistentStore(for: sharedStoreURL)

                self.sharedStoreIsReady = true
                print("[CloudSharingService] Shared store loaded: \(sharedStoreURL.lastPathComponent)")
            }
        }
    }

    private var sharedStoreFileURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("HomeMaintainerShared.store")
    }

    // MARK: - CloudKit Database Subscriptions

    private func setupDatabaseSubscriptions(container: NSPersistentCloudKitContainer) {
        let ckContainer = CKContainer(identifier: "iCloud.EstraDOS.Home-Maintainer")
        setupSubscription(in: ckContainer.privateCloudDatabase, id: "private-db-changes")
        setupSubscription(in: ckContainer.sharedCloudDatabase,  id: "shared-db-changes")
    }

    private func setupSubscription(in database: CKDatabase, id subscriptionID: String) {
        database.fetch(withSubscriptionID: subscriptionID) { existing, _ in
            guard existing == nil else { return }   // already subscribed
            let sub = CKDatabaseSubscription(subscriptionID: subscriptionID)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true  // silent push for background fetch
            sub.notificationInfo = info
            let op = CKModifySubscriptionsOperation(subscriptionsToSave: [sub], subscriptionIDsToDelete: nil)
            op.qualityOfService = .utility
            database.add(op)
        }
    }

    // MARK: - Shared Store Detection

    /// Returns true if the given PersistentIdentifier belongs to the shared CloudKit store.
    /// Relationship accesses on shared-store objects crash via ModelContext.fulfill because
    /// SwiftData's ModelContext only knows about the private store. Use this to guard any
    /// code that touches @Relationship properties on model objects from @Query results.
    func isInSharedStore(_ identifier: PersistentIdentifier) -> Bool {
        guard let sharedStore = sharedPersistentStore,
              let sharedURL = sharedStore.url else { return false }
        return identifier.storeIdentifier == sharedURL.absoluteString
    }

    // MARK: - Share a Home

    /// Retrieves (or creates) a CloudKit share link for the given home and returns its URL.
    /// Waits up to 30 seconds for CloudKit to be ready, then calls the completion on the main thread.
    func shareLink(
        for home: Home,
        from modelContext: ModelContext,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        Task { @MainActor in
            // Wait up to 30 s for the container AND a successful CloudKit setup/export event.
            var ticks = 0
            while (persistentCloudKitContainer == nil || !isCloudKitReady), ticks < 60 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                ticks += 1
            }

            guard let ckContainer = persistentCloudKitContainer, isCloudKitReady else {
                completion(.failure(SharingError.containerNotReady))
                return
            }

            guard let homeObject = try? findManagedObject(id: home.id, entityName: "Home", in: ckContainer.viewContext)
            else {
                completion(.failure(SharingError.objectNotFound))
                return
            }

            // Return the existing share URL if this home is already shared.
            if let shares = try? ckContainer.fetchShares(matching: [homeObject.objectID]),
               let existingShare = shares[homeObject.objectID] {
                // Upgrade legacy shares that were created without public access.
                if existingShare.publicPermission == .none {
                    updatePublicPermission(on: existingShare, home: home, completion: completion)
                } else if let url = existingShare.url {
                    completion(.success(url))
                } else {
                    completion(.failure(SharingError.shareURLUnavailable))
                }
            } else {
                createShareLink(for: homeObject, home: home, container: ckContainer, completion: completion)
            }
        }
    }

    private func createShareLink(
        for homeObject: NSManagedObject,
        home: Home,
        container: NSPersistentCloudKitContainer,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        print("[CloudSharingService] Calling share(_:to:) for '\(home.name)' (objectID: \(homeObject.objectID))")
        container.share([homeObject], to: nil) { _, share, ckContainer, error in
            if let error {
                print("[CloudSharingService] share(_:to:) error: \(error)")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let share else {
                DispatchQueue.main.async { completion(.failure(SharingError.shareCreationFailed)) }
                return
            }
            print("[CloudSharingService] share(_:to:) succeeded — url=\(share.url?.absoluteString ?? "nil")")

            share[CKShare.SystemFieldKey.title] = home.name as CKRecordValue
            // Allow anyone with the link to join — without this, iOS shows "Item unavailable"
            // to the recipient because the default publicPermission is .none (invite-only).
            share.publicPermission = .readWrite

            let database = (ckContainer ?? CKContainer(identifier: "iCloud.EstraDOS.Home-Maintainer")).privateCloudDatabase
            let op = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
            op.qualityOfService = .userInitiated
            op.modifyRecordsResultBlock = { result in
                DispatchQueue.main.async {
                    if case .failure(let saveError) = result {
                        print("[CloudSharingService] Failed to save share permissions: \(saveError)")
                    }
                    if let url = share.url {
                        completion(.success(url))
                    } else {
                        completion(.failure(SharingError.shareURLUnavailable))
                    }
                }
            }
            database.add(op)
        }
    }

    private func updatePublicPermission(
        on share: CKShare,
        home: Home,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        share[CKShare.SystemFieldKey.title] = home.name as CKRecordValue
        share.publicPermission = .readWrite
        let op = CKModifyRecordsOperation(recordsToSave: [share], recordIDsToDelete: nil)
        op.qualityOfService = .userInitiated
        op.modifyRecordsResultBlock = { result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    print("[CloudSharingService] Failed to upgrade share permissions: \(error)")
                    completion(.failure(error))
                    return
                }
                if let url = share.url {
                    completion(.success(url))
                } else {
                    completion(.failure(SharingError.shareURLUnavailable))
                }
            }
        }
        CKContainer(identifier: "iCloud.EstraDOS.Home-Maintainer").privateCloudDatabase.add(op)
    }

    // MARK: - Remove a Shared Home (participant leaving)

    /// Removes a home that was shared to this user (not owned by them).
    /// Uses purgeObjectsAndRecordsInZone when the zone is available, so both
    /// the local shared store and the CloudKit zone are cleaned up. Falls back
    /// to a CoreData-level delete (bypassing SwiftData cascade) when no share
    /// record is found.
    func removeSharedHome(_ home: Home) {
        guard let container = persistentCloudKitContainer,
              let sharedStore = sharedPersistentStore else {
            print("[CloudSharingService] removeSharedHome: shared store not ready")
            return
        }

        guard let homeObj = try? findManagedObject(
            id: home.id, entityName: "Home", in: container.viewContext
        ) else {
            print("[CloudSharingService] removeSharedHome: home not found in CoreData context")
            return
        }

        // Look up the CKShare so we can purge the entire shared zone cleanly.
        if let shares = try? container.fetchShares(matching: [homeObj.objectID]),
           let share = shares[homeObj.objectID] {
            let zoneID = share.recordID.zoneID
            container.purgeObjectsAndRecordsInZone(with: zoneID, in: sharedStore) { _, error in
                if let error {
                    print("[CloudSharingService] purgeObjectsAndRecordsInZone error: \(error)")
                } else {
                    print("[CloudSharingService] Shared zone purged: \(zoneID.zoneName)")
                }
            }
        } else {
            // No share record found — delete via CoreData context directly.
            // This avoids SwiftData's cascade which would fault relationships
            // through ModelContext.fulfill and crash for shared-store objects.
            container.viewContext.delete(homeObj)
            try? container.viewContext.save()
            print("[CloudSharingService] Shared home deleted via CoreData context (no share record found)")
        }
    }

    // MARK: - Accept an Incoming Share Invitation

    func acceptShare(metadata: CKShare.Metadata) {
        guard let container = persistentCloudKitContainer,
              let sharedStore = sharedPersistentStore else {
            // Shared store not yet ready — accept at the CloudKit level so the server
            // records the participation. Data will sync into the shared store once it loads.
            let op = CKAcceptSharesOperation(shareMetadatas: [metadata])
            op.qualityOfService = .userInitiated
            op.acceptSharesResultBlock = { result in
                if case .failure(let error) = result {
                    print("[CloudSharingService] CKAcceptSharesOperation error: \(error)")
                } else {
                    print("[CloudSharingService] Share accepted (shared store not yet ready; data syncs on next load)")
                }
            }
            CKContainer(identifier: "iCloud.EstraDOS.Home-Maintainer").add(op)
            return
        }

        container.acceptShareInvitations(from: [metadata], into: sharedStore) { [weak self] _, error in
            if let error {
                print("[CloudSharingService] acceptShareInvitations error: \(error)")
                DispatchQueue.main.async {
                    if error.localizedDescription.contains("owner participant") {
                        self?.shareAcceptError = "You're already the owner of this home — it's already in your app."
                    } else {
                        self?.shareAcceptError = "Could not accept the home invitation. Please try again."
                    }
                }
            } else {
                print("[CloudSharingService] Share accepted and syncing to local shared store")
            }
        }
    }

    // MARK: - Helpers

    private func findManagedObject(
        id: UUID, entityName: String, in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        // Use NSUUID (not UUID as CVarArg) to avoid NSKeyedUnarchiveFromData deprecation warning.
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    // MARK: - Errors

    enum SharingError: LocalizedError {
        case containerNotReady
        case objectNotFound
        case shareCreationFailed
        case shareURLUnavailable

        var errorDescription: String? {
            switch self {
            case .containerNotReady:    return "iCloud sync is still initializing. Please try again in a moment."
            case .objectNotFound:       return "Could not find this home in the local database."
            case .shareCreationFailed:  return "Failed to create a CloudKit share. Please try again."
            case .shareURLUnavailable:  return "The share link could not be retrieved. Please try again."
            }
        }
    }
}

// MARK: - UICloudSharingController SwiftUI wrapper

struct CloudSharingSheet: UIViewControllerRepresentable {
    let controller: UICloudSharingController
    var onDismiss: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        var onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

        func itemTitle(for csc: UICloudSharingController) -> String? { nil }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { onDismiss() }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { onDismiss() }
        func cloudSharingController(_ csc: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) { onDismiss() }
    }
}
