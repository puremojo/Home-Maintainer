
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
    /// Incremented whenever shared-store data changes (local save or CloudKit import).
    /// Views use this to force @Query recreation, since CoreData-level changes bypass SwiftData's observation hooks.
    private(set) var sharedStoreVersion: Int = 0
    /// Non-nil when share acceptance fails. ContentView observes this to show an alert.
    var shareAcceptError: String?
    /// Last export event result per store — "ok", "FAIL:<reason>", or "—" (not seen yet).
    private(set) var privateExportStatus: String = "—"
    private(set) var sharedExportStatus: String = "—"
    /// Last import event result per store.
    private(set) var privateImportStatus: String = "—"
    private(set) var sharedImportStatus: String = "—"
    /// Routing path taken for the most recent task add: "own" (owner), "par" (participant), or "—".
    private(set) var lastTaskAddPath: String = "—"
    private var eventObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    /// Metadata saved when acceptShare is called before the shared store is ready.
    /// Replayed automatically once the store finishes loading.
    private var pendingShareMetadata: CKShare.Metadata?
    /// Prevents infinite retry if the fresh store still fails to accept.
    private var hasAttemptedStoreRecovery = false
    /// Short diagnostic string set during recovery; included in the final error message
    /// so screenshots identify which path ran without needing a connected device.
    private var lastRecoveryPath = ""



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
                self.setupDatabaseSubscriptions()
                self.setupSharedStore(container: container)
            }

            // Handle CloudKit sync events — update per-store status properties so the
            // diagnostic overlay can show export/import health without needing console logs.
            if let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event {
                // Each operation fires the notification TWICE: once when it starts
                // (endDate=nil, succeeded=false, error=nil) and once when it ends
                // (endDate non-nil, succeeded=true/false, error set if failed).
                // Ignore start events — processing them as FAIL:err (succeeded=false, error=nil)
                // would permanently poison the sticky status even when the operation succeeds.
                guard event.endDate != nil else { return }

                let storeID = event.storeIdentifier
                // Classify by object identity: find which NSPersistentStore has this identifier
                // and compare it to our known sharedPersistentStore reference.
                // String matching on lastPathComponent was unreliable if the identifier format
                // differed from the URL (e.g. a UUID or abbreviated path on device).
                let isSharedStoreEvent: Bool
                if let sharedStore = self.sharedPersistentStore,
                   let container = self.persistentCloudKitContainer,
                   let matchedStore = container.persistentStoreCoordinator.persistentStores
                       .first(where: { $0.identifier == storeID }) {
                    isSharedStoreEvent = matchedStore === sharedStore
                } else {
                    // Fallback when the container or shared store isn't set up yet.
                    isSharedStoreEvent = storeID.contains("Shared") || storeID.contains("shared")
                }
                NSLog("[CloudSharingService] CloudKit event — type=%d storeID=%@ isShared=%@",
                      event.type.rawValue, storeID, isSharedStoreEvent ? "YES" : "NO")

                let status: String
                if event.succeeded {
                    status = "ok"
                } else {
                    // Truncate error so it fits in the overlay chip (wider now for better diagnosis).
                    let raw = event.error?.localizedDescription ?? "err"
                    status = "FAIL:\(raw.prefix(40))"
                    NSLog("[CloudSharingService] CloudKit event FAILED — type=%d store=%@ error=%@",
                          event.type.rawValue, storeID, raw)
                }

                // FAIL status is sticky: once a FAIL is recorded it is only overwritten
                // by another FAIL (to get the latest error text), never by ok. This prevents
                // a transient FAIL from being silently lost when a subsequent ok fires.
                // Pull-to-refresh (refreshSharedStore) resets all statuses to "—" for a clean read.
                func shouldUpdate(current: String, new: String) -> Bool {
                    // Always accept FAIL. Accept ok only if no FAIL has been seen yet.
                    return new.hasPrefix("FAIL") || !current.hasPrefix("FAIL")
                }

                switch event.type {
                case .setup:
                    if event.succeeded { self.isCloudKitReady = true }
                    NSLog("[CloudSharingService] CloudKit setup — store:%@ ok=%@", storeID, event.succeeded ? "YES" : "NO")
                case .export:
                    if isSharedStoreEvent {
                        if shouldUpdate(current: self.sharedExportStatus, new: status) { self.sharedExportStatus = status }
                    } else {
                        if shouldUpdate(current: self.privateExportStatus, new: status) { self.privateExportStatus = status }
                    }
                    if event.succeeded { self.isCloudKitReady = true }
                    NSLog("[CloudSharingService] CloudKit export — store:%@ status=%@", isSharedStoreEvent ? "SHARED" : "PRIVATE", status)
                case .import:
                    if isSharedStoreEvent {
                        if shouldUpdate(current: self.sharedImportStatus, new: status) { self.sharedImportStatus = status }
                    } else {
                        if shouldUpdate(current: self.privateImportStatus, new: status) { self.privateImportStatus = status }
                    }
                    if event.succeeded {
                        // CloudKit imported records into the private or shared store via a
                        // background context. The main viewContext's in-memory cache won't
                        // automatically reflect those new objects, so @Query won't show them
                        // until we tell the context to re-read from the persistent stores.
                        // Incrementing sharedStoreVersion forces @Query recreation in views
                        // that use it as an .id() — required because CoreData-level changes
                        // bypass SwiftData's own observation hooks.
                        self.persistentCloudKitContainer?.viewContext.refreshAllObjects()
                        self.sharedStoreVersion += 1
                        NSLog("[CloudSharingService] CloudKit import OK — store:%@ version→%d",
                              isSharedStoreEvent ? "SHARED" : "PRIVATE", self.sharedStoreVersion)
                    }
                @unknown default:
                    break
                }
            }
        }

        // When the app returns to the foreground, force the main context to re-read
        // from both stores. This catches any CloudKit changes that synced while the
        // app was suspended (import events that fired with no active observer).
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.sharedStoreIsReady else { return }
            self.persistentCloudKitContainer?.viewContext.refreshAllObjects()
            self.sharedStoreVersion += 1
        }
    }

    deinit {
        if let observer = eventObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = foregroundObserver {
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
            NSLog("[CloudSharingService] Shared store already present")
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
                NSLog("[CloudSharingService] Shared store failed to load: \(error)")
                return
            }
            guard loadedDesc.url == sharedStoreURL else { return }
            DispatchQueue.main.async {
                self.sharedPersistentStore = container.persistentStoreCoordinator
                    .persistentStore(for: sharedStoreURL)

                self.sharedStoreIsReady = true
                NSLog("[CloudSharingService] Shared store loaded: \(sharedStoreURL.lastPathComponent)")

                // If a share link was tapped before the store was ready, accept it now.
                // CKAcceptSharesOperation (the earlier fallback) only records participation
                // on the server; calling acceptShareInvitations here imports the actual data.
                if let metadata = self.pendingShareMetadata {
                    self.pendingShareMetadata = nil
                    self.acceptShare(metadata: metadata)
                }
            }
        }
    }

    private var sharedStoreFileURL: URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("HomeMaintainerShared.store")
    }

    // MARK: - CloudKit Database Subscriptions

    /// Ensures CKDatabaseSubscription records exist for both the private and shared
    /// CloudKit databases. NSPersistentCloudKitContainer sets up zone-level subscriptions
    /// for stores it manages at init time, but the shared store is appended post-init
    /// (in setupSharedStore), so the container never registers a subscription for the
    /// shared database. Without an explicit CKDatabaseSubscription on the shared DB,
    /// CloudKit cannot deliver a silent push when a participant writes a record — the
    /// host falls back to periodic polling (30-60 min intervals) instead of near-instant sync.
    private func setupDatabaseSubscriptions() {
        let ckContainer = CKContainer(identifier: "iCloud.EstraDOS.Home-Maintainer")
        setupSubscription(in: ckContainer.privateCloudDatabase, id: "private-db-changes")
        setupSubscription(in: ckContainer.sharedCloudDatabase,  id: "shared-db-changes")
    }

    private func setupSubscription(in database: CKDatabase, id subscriptionID: String) {
        database.fetch(withSubscriptionID: subscriptionID) { existing, _ in
            guard existing == nil else { return }   // already subscribed — no-op
            let sub = CKDatabaseSubscription(subscriptionID: subscriptionID)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true  // silent push wakes NSPersistentCloudKitContainer
            sub.notificationInfo = info
            let op = CKModifySubscriptionsOperation(subscriptionsToSave: [sub], subscriptionIDsToDelete: nil)
            op.qualityOfService = .utility
            database.add(op)
        }
    }

    // MARK: - Shared Store Detection

    /// Returns true if the object with the given entity name and UUID lives in the shared
    /// CloudKit store. Uses the same CoreData affectedStores technique as isCurrentUserOwner
    /// so it is reliable regardless of PersistentIdentifier.storeIdentifier formatting.
    /// The fetch is limited to 1 row in a single SQLite file and is fast to call per-render.
    func isInSharedStore(entityName: String, id: UUID) -> Bool {
        guard let sharedStore = sharedPersistentStore,
              let container = persistentCloudKitContainer else { return false }
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        request.affectedStores = [sharedStore]
        return (try? container.viewContext.fetch(request).first) != nil
    }

    /// Convenience overload using a PersistentIdentifier's entity name — still requires
    /// the model's id UUID to be passed separately since the identifier's internal object
    /// ID is not publicly accessible from SwiftData.
    func isInSharedStore(_ identifier: PersistentIdentifier) -> Bool {
        // Kept for call sites that already have a PersistentIdentifier but no UUID.
        // Uses storeIdentifier as a fast pre-check, falls back to false if unavailable.
        guard let sharedStore = sharedPersistentStore,
              let sharedURL = sharedStore.url,
              let storeID = identifier.storeIdentifier else { return false }
        return storeID == sharedURL.absoluteString
            || storeID == sharedURL.path
            || storeID.hasSuffix(sharedURL.lastPathComponent)
    }

    // MARK: - Shared Store Writes

    /// Creates an NSManagedObject in the shared CloudKit store so the record is
    /// visible to all home participants (including the owner on their device).
    /// Does NOT save — call saveSharedContext() once all inserts for a logical
    /// operation are done to upload them in a single CloudKit transaction.
    /// Must be called on the main thread (viewContext is main-queue confined).
    @discardableResult
    func insertIntoSharedStore(
        entityName: String,
        configure: (NSManagedObject) -> Void
    ) throws -> NSManagedObject {
        guard let container = persistentCloudKitContainer,
              let sharedStore = sharedPersistentStore else {
            throw SharingError.containerNotReady
        }
        let ctx = container.viewContext
        guard let entity = NSEntityDescription.entity(forEntityName: entityName, in: ctx) else {
            throw SharingError.objectNotFound
        }
        let obj = NSManagedObject(entity: entity, insertInto: ctx)
        // Assign to the shared store BEFORE configure so any relationship set in
        // configure (e.g. task.home = sharedStoreHome) is a same-store relationship
        // from the moment it is made. If configure runs first while obj is still in
        // the default store, CoreData treats home (shared store) as a cross-store
        // relationship and silently drops it at save time — task.home becomes nil,
        // zone inference falls back to _defaultZone, and the task is never visible
        // to the home owner. Same root cause and fix as insertLinkedToHome.
        ctx.assign(obj, to: sharedStore)
        configure(obj)
        return obj
    }

    /// Like insertIntoSharedStore, but for the home OWNER: inserts into the CoreData context
    /// assigned to the PRIVATE store so zone inference can follow the `home` relationship
    /// to the home's shared CloudKit zone, making the new record visible to participants.
    /// Contrast with insertIntoSharedStore (used for PARTICIPANT writes) which explicitly
    /// assigns to sharedStore via ctx.assign.
    ///
    /// CRITICAL order: ctx.assign MUST run before configure() sets any relationships.
    /// Without pre-assignment, the new object is tentatively routed to the shared store
    /// (most-recently-added). Setting task.home while obj is in the shared store and homeObj
    /// is in the private store creates a cross-store relationship — CoreData silently drops it
    /// on save, leaving task.home=nil, so zone inference falls back to _defaultZone.
    @discardableResult
    func insertLinkedToHome(
        entityName: String,
        configure: (NSManagedObject) -> Void
    ) throws -> NSManagedObject {
        guard let container = persistentCloudKitContainer else {
            throw SharingError.containerNotReady
        }
        let ctx = container.viewContext
        guard let entity = NSEntityDescription.entity(forEntityName: entityName, in: ctx) else {
            throw SharingError.objectNotFound
        }
        guard let privateStore = container.persistentStoreCoordinator.persistentStores
            .first(where: { $0 != sharedPersistentStore }) else {
            throw SharingError.containerNotReady
        }
        let obj = NSManagedObject(entity: entity, insertInto: ctx)
        // Assign to the private store BEFORE configure() sets relationships.
        // This ensures task.home = homeObj (homeObj is in private store) is a same-store
        // relationship from the moment it's set, so CoreData never has cause to drop it.
        ctx.assign(obj, to: privateStore)
        configure(obj)
        return obj
    }

    /// Saves inserted objects to the persistent store. NSPersistentCloudKitContainer infers
    /// the correct CloudKit zone from the `home` relationship at sync time, placing the records
    /// in the home's shared zone so participants see them. Do NOT call container.share() here —
    /// it traverses all relationships via performBlockAndWait: and crashes when relationship
    /// faults can't be resolved across store boundaries (see build 40 crash log).
    func addObjectsToHomeShare(objects: [NSManagedObject], homeID: UUID) {
        NSLog("[CloudSharingService] addObjectsToHomeShare: saving \(objects.count) object(s); zone inference will assign to home's shared zone")
        lastTaskAddPath = "par"
        try? saveSharedContext()
    }

    /// Owner path: sets task.home to the private-store home so NSPersistentCloudKitContainer's
    /// zone inference places the task in the home's shared CloudKit zone (zone Z) at export time.
    ///
    /// container.share(_:to:) is deliberately NOT used. It traverses faulted relationship
    /// collections inside performBlockAndWait (PFCloudKitSerializer.createSetOfObjectIDs…)
    /// → EXC_CRASH SIGABRT across all tested builds (40/44/48/49/50/51). Zone inference via
    /// the task.home relationship achieves the same zone assignment without any API call,
    /// provided homeObj is from the PRIVATE store (see findHomeManagedObjectInPrivateStore).
    ///
    /// WHY private store is required: the owner's shared store mirrors zone Z records from the
    /// shared CloudKit DB, so the home appears in BOTH stores on the owner's device. If the
    /// shared-store copy is used, task (private) + home (shared) is a cross-store relationship
    /// that CoreData silently drops at save time — task.home becomes nil, zone inference falls
    /// back to _defaultZone, and participants never see the task.
    func addObjectsToOwnerShare(objects: [NSManagedObject], homeID: UUID) {
        guard persistentCloudKitContainer != nil else {
            try? saveSharedContext()
            return
        }

        guard let homeObj = findHomeManagedObjectInPrivateStore(id: homeID) else {
            NSLog("[CloudSharingService] addObjectsToOwnerShare: home not found in private store — plain save")
            try? saveSharedContext()
            return
        }

        lastTaskAddPath = "own"
        // task (private store) + home (private store, zone Z) → valid same-store relationship.
        // NSPersistentCloudKitContainer infers zone Z from the home relationship at export time.
        for obj in objects where obj.entity.propertiesByName["home"] != nil {
            obj.setValue(homeObj, forKey: "home")
        }
        try? saveSharedContext()
    }

    /// Saves all pending shared-store inserts in a single CloudKit transaction.
    func saveSharedContext() throws {
        guard let container = persistentCloudKitContainer else {
            throw SharingError.containerNotReady
        }
        if container.viewContext.hasChanges {
            try container.viewContext.save()
        }
        // Shared-store inserts go through Core Data APIs, bypassing SwiftData's
        // observation hooks. refreshAllObjects() signals the CoreData context but
        // SwiftData @Query doesn't observe cross-context saves — views must use
        // sharedStoreVersion as an .id() key to force @Query recreation.
        container.viewContext.refreshAllObjects()
        sharedStoreVersion += 1
    }

    /// Inserts a MaintenanceRecord into the shared store linked to the given task.
    /// Used by CloseTaskSheet and reopen actions so history is visible to all participants.
    func insertMaintenanceRecord(taskID: UUID, completedDate: Date, notes: String, action: TaskAction) {
        guard let container = persistentCloudKitContainer else { return }
        do {
            let taskObj = try findManagedObject(id: taskID, entityName: "MaintenanceTask", in: container.viewContext)
            try insertIntoSharedStore(entityName: "MaintenanceRecord") { obj in
                obj.setValue(UUID(), forKey: "id")
                obj.setValue(completedDate, forKey: "completedDate")
                obj.setValue(notes, forKey: "notes")
                obj.setValue(action.rawValue, forKey: "action")
                obj.setValue(taskObj, forKey: "task")
            }
            try saveSharedContext()
        } catch {
            NSLog("[CloudSharingService] insertMaintenanceRecord failed: \(error)")
        }
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
                    // Local store has the share but the URL hasn't synced back from CloudKit
                    // yet (common on second attempt before the next sync cycle). Fetch the
                    // live share record from CloudKit to get the URL directly.
                    fetchShareURL(from: existingShare, completion: completion)
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
        NSLog("[CloudSharingService] Calling share(_:to:) for '\(home.name)' (objectID: \(homeObject.objectID))")
        container.share([homeObject], to: nil) { _, share, ckContainer, error in
            if let error {
                NSLog("[CloudSharingService] share(_:to:) error: \(error)")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let share else {
                DispatchQueue.main.async { completion(.failure(SharingError.shareCreationFailed)) }
                return
            }
            NSLog("[CloudSharingService] share(_:to:) succeeded — url=\(share.url?.absoluteString ?? "nil")")

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
                        NSLog("[CloudSharingService] Failed to save share permissions: \(saveError)")
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

    private func fetchShareURL(
        from share: CKShare,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let db = CKContainer(identifier: "iCloud.EstraDOS.Home-Maintainer").privateCloudDatabase
        db.fetch(withRecordID: share.recordID) { record, error in
            DispatchQueue.main.async {
                if let fetched = record as? CKShare, let url = fetched.url {
                    completion(.success(url))
                } else {
                    completion(.failure(error ?? SharingError.shareURLUnavailable))
                }
            }
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
                    NSLog("[CloudSharingService] Failed to upgrade share permissions: \(error)")
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
            NSLog("[CloudSharingService] removeSharedHome: shared store not ready")
            return
        }

        guard let homeObj = try? findManagedObject(
            id: home.id, entityName: "Home", in: container.viewContext
        ) else {
            NSLog("[CloudSharingService] removeSharedHome: home not found in CoreData context")
            return
        }

        // Look up the CKShare so we can purge the entire shared zone cleanly.
        if let shares = try? container.fetchShares(matching: [homeObj.objectID]),
           let share = shares[homeObj.objectID] {
            let zoneID = share.recordID.zoneID
            container.purgeObjectsAndRecordsInZone(with: zoneID, in: sharedStore) { _, error in
                if let error {
                    NSLog("[CloudSharingService] purgeObjectsAndRecordsInZone error: \(error)")
                } else {
                    NSLog("[CloudSharingService] Shared zone purged: \(zoneID.zoneName)")
                }
            }
        } else {
            // No share record found — delete via CoreData context directly.
            // This avoids SwiftData's cascade which would fault relationships
            // through ModelContext.fulfill and crash for shared-store objects.
            container.viewContext.delete(homeObj)
            try? container.viewContext.save()
            NSLog("[CloudSharingService] Shared home deleted via CoreData context (no share record found)")
        }
    }

    // MARK: - Accept an Incoming Share Invitation

    func acceptShare(metadata: CKShare.Metadata) {
        guard let container = persistentCloudKitContainer,
              let sharedStore = sharedPersistentStore else {
            // Shared store not yet ready — save the metadata so setupSharedStore can replay
            // acceptShareInvitations once the store is loaded (which actually imports the data).
            // Also accept at the CloudKit level immediately so the server records participation.
            pendingShareMetadata = metadata
            let op = CKAcceptSharesOperation(shareMetadatas: [metadata])
            op.qualityOfService = .userInitiated
            op.acceptSharesResultBlock = { result in
                if case .failure(let error) = result {
                    let nsErr = error as NSError
                    NSLog("[CloudSharingService] CKAcceptSharesOperation error: \(error) [domain=\(nsErr.domain) code=\(nsErr.code)]")
                } else {
                    NSLog("[CloudSharingService] Share pre-accepted at server level; awaiting shared store to import data")
                }
            }
            CKContainer(identifier: "iCloud.EstraDOS.Home-Maintainer").add(op)
            return
        }

        container.acceptShareInvitations(from: [metadata], into: sharedStore) { [weak self] _, error in
            if let error {
                let nsErr = error as NSError
                NSLog("[CloudSharingService] acceptShareInvitations error: \(error) [domain=\(nsErr.domain) code=\(nsErr.code)]")
                NSLog("[CloudSharingService]   userInfo: \(nsErr.userInfo)")

                // acceptShareInvitations returns NSCocoaErrorDomain 134406 when the mirroring
                // delegate can't initialize. The nested cause (visible in the description) is
                // 134060 — zone-less objects left in the shared store from a previous share that
                // CloudKit re-syncs before acceptShareInvitations runs. Purge the stale zones
                // first (stops CloudKit from re-syncing them), then retry.
                // NOTE: the outer code is 134406, NOT 134060 — always check both.
                let isMirroringError = nsErr.domain == NSCocoaErrorDomain &&
                    (nsErr.code == 134406 || nsErr.code == 134060)
                if isMirroringError, let self, !self.hasAttemptedStoreRecovery {
                    self.hasAttemptedStoreRecovery = true
                    DispatchQueue.main.async {
                        self.purgeStaleZonesAndRetry(metadata: metadata, container: container, sharedStore: sharedStore)
                    }
                    return
                }

                DispatchQueue.main.async {
                    if error.localizedDescription.contains("owner participant") {
                        self?.shareAcceptError = "You're already the owner of this home — it's already in your app."
                    } else if isMirroringError {
                        // Zone purge ran but the mirroring delegate still can't initialize.
                        // The container's in-memory state needs a fresh launch to fully reset.
                        let path = self?.lastRecoveryPath ?? "unknown"
                        self?.shareAcceptError = "Your app's sync data was refreshed. Please force-quit the app, reopen it, then tap the invitation link again. [path:\(path)]"
                    } else {
                        let detail = "\(error.localizedDescription) [\(nsErr.domain) \(nsErr.code)]"
                        self?.shareAcceptError = "Could not accept the home invitation.\n\n\(detail)"
                    }
                }
            } else {
                NSLog("[CloudSharingService] Share accepted and syncing to local shared store")
                // Eagerly refresh so @Query picks up any records that were already present
                // in the shared store before the import event fires. Increment sharedStoreVersion
                // so views using .id(sharedStoreVersion) recreate their @Query immediately.
                DispatchQueue.main.async {
                    self?.persistentCloudKitContainer?.viewContext.refreshAllObjects()
                    self?.sharedStoreVersion += 1
                }
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

    /// Reads `taskDocuments` from a shared-store MaintenanceTask via CoreData's viewContext,
    /// bypassing ModelContext.fulfill. `[TaskDocument]?` is a Codable transformable attribute;
    /// accessing it through NSManagedObject.value(forKey:) uses the registered transformer safely.
    func fetchTaskDocuments(for taskID: UUID) -> [TaskDocument] {
        guard let sharedStore = sharedPersistentStore,
              let container = persistentCloudKitContainer else { return [] }
        let request = NSFetchRequest<NSManagedObject>(entityName: "MaintenanceTask")
        request.predicate = NSPredicate(format: "id == %@", taskID as NSUUID)
        request.fetchLimit = 1
        request.affectedStores = [sharedStore]
        guard let obj = try? container.viewContext.fetch(request).first else { return [] }
        return (obj.value(forKey: "taskDocuments") as? [TaskDocument]) ?? []
    }

    /// Looks up a Home NSManagedObject across ALL stores by UUID.
    /// Used by the participant path — the participant's home lives in the shared store
    /// so an unconstrained search is correct there.
    func findHomeManagedObject(id: UUID) -> NSManagedObject? {
        guard let container = persistentCloudKitContainer else { return nil }
        let request = NSFetchRequest<NSManagedObject>(entityName: "Home")
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try? container.viewContext.fetch(request).first
    }

    /// Looks up a Home NSManagedObject in the PRIVATE store only.
    /// Must be used by the owner path so that setting `task.home = homeObj` never
    /// creates a cross-store relationship. If findHomeManagedObject returned the
    /// shared-store copy of the home (NSPersistentCloudKitContainer can mirror the
    /// home into the shared store because the zone is visible from the shared DB),
    /// CoreData silently drops the relationship on save — zone inference loses the
    /// link and the task ends up in _defaultZone instead of the shared zone.
    func findHomeManagedObjectInPrivateStore(id: UUID) -> NSManagedObject? {
        guard let container = persistentCloudKitContainer else { return nil }
        guard let privateStore = container.persistentStoreCoordinator.persistentStores
            .first(where: { $0 != sharedPersistentStore }) else { return nil }
        let request = NSFetchRequest<NSManagedObject>(entityName: "Home")
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        request.affectedStores = [privateStore]
        let result = try? container.viewContext.fetch(request).first
        NSLog("[CloudSharingService] findHomeManagedObjectInPrivateStore id=%@ found=%@",
              id.uuidString, result != nil ? "YES" : "NO")
        return result
    }

    /// Forces the main context to re-read from both stores. Call from pull-to-refresh
    /// or any manual sync trigger — does not request a new CloudKit download (that is
    /// driven by push notifications), but picks up any records already imported.
    /// Also resets all diagnostic status strings so the next sync cycle gives a clean read
    /// (FAIL statuses are sticky until this reset, so they don't get overwritten by ok).
    func refreshSharedStore() {
        persistentCloudKitContainer?.viewContext.refreshAllObjects()
        sharedStoreVersion += 1
        privateExportStatus = "—"
        sharedExportStatus = "—"
        privateImportStatus = "—"
        sharedImportStatus = "—"
    }

    /// True if the current user OWNS this home and has already shared it via CloudKit.
    /// Add-item views use this to route owner writes through insertLinkedToHome rather than
    /// the SwiftData modelContext — zone assignment must follow the home relationship so new
    /// records land in the shared CloudKit zone and become visible to participants.
    func isOwnedAndShared(homeID: UUID) -> Bool {
        guard let container = persistentCloudKitContainer,
              let homeObj = try? findManagedObject(id: homeID, entityName: "Home", in: container.viewContext) else { return false }
        return (try? container.fetchShares(matching: [homeObj.objectID]))?[homeObj.objectID] != nil
    }

    /// Primary recovery for NSCocoaErrorDomain 134060. Fetches all zones from the shared
    /// CloudKit database and purges any that aren't the incoming share's zone. Purging
    /// removes the local objects AND tells NSPersistentCloudKitContainer to stop syncing
    /// those zones, preventing them from re-appearing in a fresh store. Falls back to
    /// recoverFromStaledSharedStore when there are no CloudKit zones to purge.
    private func purgeStaleZonesAndRetry(
        metadata: CKShare.Metadata,
        container: NSPersistentCloudKitContainer,
        sharedStore: NSPersistentStore
    ) {
        let incomingZoneID = metadata.share.recordID.zoneID
        let ckContainer = CKContainer(identifier: "iCloud.EstraDOS.Home-Maintainer")

        ckContainer.sharedCloudDatabase.fetchAllRecordZones { [weak self] zones, fetchError in
            guard let self else { return }

            if let fetchError {
                NSLog("[CloudSharingService] fetchAllRecordZones error: \(fetchError) — falling back to file wipe")
                DispatchQueue.main.async {
                    self.lastRecoveryPath = "fetch-failed→wipe"
                    self.recoverFromStaledSharedStore(metadata: metadata, container: container)
                }
                return
            }

            let staleZoneIDs = (zones ?? []).map(\.zoneID).filter { $0 != incomingZoneID }
            NSLog("[CloudSharingService] Found \(staleZoneIDs.count) stale zone(s) to purge before retry")

            guard !staleZoneIDs.isEmpty else {
                // No CloudKit zones — records are local-only orphans. File wipe is safe here
                // because there is nothing in CloudKit to re-sync them from.
                DispatchQueue.main.async {
                    self.lastRecoveryPath = "no-ck-zones→wipe"
                    self.recoverFromStaledSharedStore(metadata: metadata, container: container)
                }
                return
            }

            // Track purge failures; if any zone couldn't be purged the stale records
            // will still be present and the retry would fail. In that case fall back
            // to a full store wipe instead of retrying against a dirty store.
            var anyPurgeFailed = false
            let group = DispatchGroup()
            for zoneID in staleZoneIDs {
                group.enter()
                container.purgeObjectsAndRecordsInZone(with: zoneID, in: sharedStore) { _, error in
                    if let error {
                        NSLog("[CloudSharingService] Purge \(zoneID.zoneName) error: \(error)")
                        anyPurgeFailed = true
                    } else {
                        NSLog("[CloudSharingService] Purged stale zone: \(zoneID.zoneName)")
                    }
                    group.leave()
                }
            }

            group.notify(queue: .main) { [weak self] in
                guard let self else { return }
                if anyPurgeFailed {
                    // At least one purge failed — stale records may remain.
                    // Wipe the store file so the fresh store starts completely clean.
                    self.lastRecoveryPath = "purge:\(staleZoneIDs.count)zones:some-failed→wipe"
                    self.recoverFromStaledSharedStore(metadata: metadata, container: container)
                } else {
                    // All stale zones cleared — retry acceptance against the clean store
                    self.lastRecoveryPath = "purge:\(staleZoneIDs.count)zones:ok→retry"
                    self.acceptShare(metadata: metadata)
                }
            }
        }
    }

    /// Fallback recovery for 134060 when no CloudKit zones exist to purge (records are
    /// local-only orphans). Wipes the shared store SQLite files and rebuilds a clean store.
    /// Since there are no CloudKit zones to re-sync the orphans, the fresh store will be
    /// empty and the pending acceptance will succeed on the next loadPersistentStores callback.
    private func recoverFromStaledSharedStore(metadata: CKShare.Metadata, container: NSPersistentCloudKitContainer) {
        NSLog("[CloudSharingService] Shared store has local-only orphan objects — wiping and rebuilding")
        let url = sharedStoreFileURL

        if let store = sharedPersistentStore {
            try? container.persistentStoreCoordinator.remove(store)
        }

        // Delete the SQLite file plus its WAL journal and shared-memory sidecar.
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))

        sharedPersistentStore = nil
        sharedStoreIsReady = false

        // Remove the stale description so setupSharedStore appends a fresh one and
        // loadPersistentStores doesn't see a duplicate URL.
        container.persistentStoreDescriptions.removeAll { $0.url == url }

        // Auto-retry is safe here: no CloudKit zones exist to re-sync the orphaned records,
        // so the fresh store will be clean when acceptShare runs from pendingShareMetadata.
        if lastRecoveryPath.isEmpty { lastRecoveryPath = "wipe-only" }
        pendingShareMetadata = metadata

        setupSharedStore(container: container)
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
