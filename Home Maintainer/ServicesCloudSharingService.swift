
//
//  ServicesCloudSharingService.swift
//  Home Maintainer
//
//  Manages CloudKit zone sharing for Home objects via NSPersistentCloudKitContainer.
//  Both the private and shared stores are configured at init time — this is the
//  critical detail that makes NSPersistentCloudKitContainer register push-driven
//  subscriptions for BOTH stores (eliminating the old 30-minute polling fallback).
//

import Foundation
import SwiftUI
import CoreData
import CloudKit
import UIKit

@Observable
final class CloudSharingService {

    // MARK: - Shared singleton (set at app startup so SceneDelegate can reach it)
    static var shared: CloudSharingService?

    // MARK: - State

    private(set) var persistentCloudKitContainer: NSPersistentCloudKitContainer?
    /// True after CloudKit completes a successful setup or export.
    private(set) var isCloudKitReady = false
    /// The shared-database persistent store.
    private(set) var sharedPersistentStore: NSPersistentStore?
    /// True once the shared store is loaded and ready to accept shares.
    private(set) var sharedStoreIsReady = false
    /// Incremented whenever shared-store data changes (local save or CloudKit import).
    /// Views use this to force @FetchRequest recreation.
    private(set) var sharedStoreVersion: Int = 0
    /// Non-nil when share acceptance fails. ContentView observes this to show an alert.
    var shareAcceptError: String?
    /// Last export event result per store.
    private(set) var privateExportStatus: String = "—"
    private(set) var sharedExportStatus: String = "—"
    /// Last import event result per store.
    private(set) var privateImportStatus: String = "—"
    private(set) var sharedImportStatus: String = "—"
    /// Routing path taken for the most recent task add.
    private(set) var lastTaskAddPath: String = "—"
    private var eventObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    /// Saved when acceptShare is called before the shared store is ready (recovery path).
    private var pendingShareMetadata: CKShare.Metadata?
    /// Prevents infinite retry if the fresh store still fails to accept.
    private var hasAttemptedStoreRecovery = false
    private var lastRecoveryPath = ""

    // MARK: - Convenience accessor

    var viewContext: NSManagedObjectContext {
        persistentCloudKitContainer!.viewContext
    }

    // MARK: - Init

    init(container: NSPersistentCloudKitContainer) {
        persistentCloudKitContainer = container

        // Locate the shared store by URL.
        let sharedURL = Self.makeSharedStoreURL()
        sharedPersistentStore = container.persistentStoreCoordinator.persistentStores
            .first(where: { $0.url == sharedURL })
        sharedStoreIsReady = sharedPersistentStore != nil

        // Observe CloudKit sync events for diagnostic status and context refresh.
        // Container capture is no longer needed here — we receive it in init().
        eventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }

            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }

            // Ignore start events (endDate == nil).
            guard event.endDate != nil else { return }

            let storeID = event.storeIdentifier
            let isSharedStoreEvent: Bool
            if let sharedStore = self.sharedPersistentStore,
               let container = self.persistentCloudKitContainer,
               let matchedStore = container.persistentStoreCoordinator.persistentStores
                   .first(where: { $0.identifier == storeID }) {
                isSharedStoreEvent = matchedStore === sharedStore
            } else {
                isSharedStoreEvent = storeID.contains("Shared") || storeID.contains("shared")
            }

            NSLog("[CloudSharingService] CloudKit event — type=%d storeID=%@ isShared=%@",
                  event.type.rawValue, storeID, isSharedStoreEvent ? "YES" : "NO")

            let status: String
            if event.succeeded {
                status = "ok"
            } else {
                let raw = event.error?.localizedDescription ?? "err"
                status = "FAIL:\(raw.prefix(40))"
                NSLog("[CloudSharingService] CloudKit event FAILED — type=%d store=%@ error=%@",
                      event.type.rawValue, storeID, raw)
            }

            func shouldUpdate(current: String, new: String) -> Bool {
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
                    self.persistentCloudKitContainer?.viewContext.refreshAllObjects()
                    self.sharedStoreVersion += 1
                    NSLog("[CloudSharingService] CloudKit import OK — store:%@ version→%d",
                          isSharedStoreEvent ? "SHARED" : "PRIVATE", self.sharedStoreVersion)
                }
            @unknown default:
                break
            }
        }

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
        if let observer = eventObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = foregroundObserver { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - Store URL

    static func makeSharedStoreURL() -> URL {
        NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("HomeMaintainerShared.sqlite")
    }

    // MARK: - Shared Store Detection

    func isInSharedStore(entityName: String, id: UUID) -> Bool {
        guard let sharedStore = sharedPersistentStore,
              let container = persistentCloudKitContainer else { return false }
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        request.affectedStores = [sharedStore]
        return (try? container.viewContext.fetch(request).first) != nil
    }

    // MARK: - Shared Store Writes

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
        ctx.assign(obj, to: sharedStore)
        configure(obj)
        return obj
    }

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
        ctx.assign(obj, to: privateStore)
        configure(obj)
        return obj
    }

    func addObjectsToHomeShare(objects: [NSManagedObject], homeID: UUID) {
        NSLog("[CloudSharingService] addObjectsToHomeShare: saving \(objects.count) object(s)")
        lastTaskAddPath = "par"
        try? saveSharedContext()
    }

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
        for obj in objects where obj.entity.propertiesByName["home"] != nil {
            obj.setValue(homeObj, forKey: "home")
        }
        try? saveSharedContext()
    }

    func saveSharedContext() throws {
        guard let container = persistentCloudKitContainer else {
            throw SharingError.containerNotReady
        }
        if container.viewContext.hasChanges {
            try container.viewContext.save()
        }
        container.viewContext.refreshAllObjects()
        sharedStoreVersion += 1
    }

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

    func shareLink(
        for home: Home,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        Task { @MainActor in
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

            if let shares = try? ckContainer.fetchShares(matching: [homeObject.objectID]),
               let existingShare = shares[homeObject.objectID] {
                if existingShare.publicPermission == .none {
                    updatePublicPermission(on: existingShare, home: home, completion: completion)
                } else if let url = existingShare.url {
                    completion(.success(url))
                } else {
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

    func removeSharedHome(_ home: Home) {
        guard let container = persistentCloudKitContainer,
              let sharedStore = sharedPersistentStore else {
            NSLog("[CloudSharingService] removeSharedHome: shared store not ready")
            return
        }

        guard let homeObj = try? findManagedObject(id: home.id, entityName: "Home", in: container.viewContext) else {
            NSLog("[CloudSharingService] removeSharedHome: home not found in CoreData context")
            return
        }

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
            container.viewContext.delete(homeObj)
            try? container.viewContext.save()
            NSLog("[CloudSharingService] Shared home deleted via CoreData context (no share record found)")
        }
    }

    // MARK: - Accept an Incoming Share Invitation

    func acceptShare(metadata: CKShare.Metadata) {
        guard let container = persistentCloudKitContainer,
              let sharedStore = sharedPersistentStore else {
            pendingShareMetadata = metadata
            let op = CKAcceptSharesOperation(shareMetadatas: [metadata])
            op.qualityOfService = .userInitiated
            op.acceptSharesResultBlock = { result in
                if case .failure(let error) = result {
                    let nsErr = error as NSError
                    NSLog("[CloudSharingService] CKAcceptSharesOperation error: \(error) [domain=\(nsErr.domain) code=\(nsErr.code)]")
                } else {
                    NSLog("[CloudSharingService] Share pre-accepted at server level")
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
                        let path = self?.lastRecoveryPath ?? "unknown"
                        self?.shareAcceptError = "Your app's sync data was refreshed. Please force-quit the app, reopen it, then tap the invitation link again. [path:\(path)]"
                    } else {
                        let detail = "\(error.localizedDescription) [\(nsErr.domain) \(nsErr.code)]"
                        self?.shareAcceptError = "Could not accept the home invitation.\n\n\(detail)"
                    }
                }
            } else {
                NSLog("[CloudSharingService] Share accepted and syncing to local shared store")
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
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// Reads taskDocumentsJSON from a MaintenanceTask via CoreData's viewContext.
    func fetchTaskDocuments(for taskID: UUID) -> [TaskDocument] {
        guard let sharedStore = sharedPersistentStore,
              let container = persistentCloudKitContainer else { return [] }
        let request = NSFetchRequest<NSManagedObject>(entityName: "MaintenanceTask")
        request.predicate = NSPredicate(format: "id == %@", taskID as NSUUID)
        request.fetchLimit = 1
        request.affectedStores = [sharedStore]
        guard let obj = try? container.viewContext.fetch(request).first else { return [] }
        let json = obj.value(forKey: "taskDocumentsJSON") as? String
        return jsonDecode(from: json) ?? []
    }

    func findHomeManagedObject(id: UUID) -> NSManagedObject? {
        guard let container = persistentCloudKitContainer else { return nil }
        let request = NSFetchRequest<NSManagedObject>(entityName: "Home")
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try? container.viewContext.fetch(request).first
    }

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

    func refreshSharedStore() {
        persistentCloudKitContainer?.viewContext.refreshAllObjects()
        sharedStoreVersion += 1
        privateExportStatus = "—"
        sharedExportStatus = "—"
        privateImportStatus = "—"
        sharedImportStatus = "—"
    }

    func isOwnedAndShared(homeID: UUID) -> Bool {
        guard let container = persistentCloudKitContainer,
              let homeObj = try? findManagedObject(id: homeID, entityName: "Home", in: container.viewContext) else { return false }
        return (try? container.fetchShares(matching: [homeObj.objectID]))?[homeObj.objectID] != nil
    }

    // MARK: - Recovery

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
                DispatchQueue.main.async {
                    self.lastRecoveryPath = "no-ck-zones→wipe"
                    self.recoverFromStaledSharedStore(metadata: metadata, container: container)
                }
                return
            }

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
                    self.lastRecoveryPath = "purge:\(staleZoneIDs.count)zones:some-failed→wipe"
                    self.recoverFromStaledSharedStore(metadata: metadata, container: container)
                } else {
                    self.lastRecoveryPath = "purge:\(staleZoneIDs.count)zones:ok→retry"
                    self.acceptShare(metadata: metadata)
                }
            }
        }
    }

    private func recoverFromStaledSharedStore(metadata: CKShare.Metadata, container: NSPersistentCloudKitContainer) {
        NSLog("[CloudSharingService] Shared store has stale data — wiping and rebuilding")
        let url = Self.makeSharedStoreURL()

        if let store = sharedPersistentStore {
            try? container.persistentStoreCoordinator.remove(store)
        }

        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))

        sharedPersistentStore = nil
        sharedStoreIsReady = false

        if lastRecoveryPath.isEmpty { lastRecoveryPath = "wipe-only" }
        pendingShareMetadata = metadata

        reloadSharedStore(container: container)
    }

    /// Re-attaches the shared store after a wipe. Called only during recovery.
    private func reloadSharedStore(container: NSPersistentCloudKitContainer) {
        let url = Self.makeSharedStoreURL()
        let desc = NSPersistentStoreDescription(url: url)
        let ckOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.EstraDOS.Home-Maintainer")
        ckOptions.databaseScope = .shared
        desc.cloudKitContainerOptions = ckOptions

        // Remove any previous description with this URL so loadPersistentStores sees it as new.
        container.persistentStoreDescriptions.removeAll { $0.url == url }
        container.persistentStoreDescriptions.append(desc)

        container.loadPersistentStores { [weak self] loadedDesc, error in
            guard let self else { return }
            if let error {
                NSLog("[CloudSharingService] Failed to reload shared store: \(error)")
                return
            }
            guard loadedDesc.url == url else { return }
            DispatchQueue.main.async {
                self.sharedPersistentStore = container.persistentStoreCoordinator.persistentStore(for: url)
                self.sharedStoreIsReady = true
                NSLog("[CloudSharingService] Shared store reloaded: \(url.lastPathComponent)")
                if let metadata = self.pendingShareMetadata {
                    self.pendingShareMetadata = nil
                    self.acceptShare(metadata: metadata)
                }
            }
        }
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
