
//
//  ServicesCloudSharingService.swift
//  Home Maintainer
//
//  Direct CloudKit sync engine.  Replaces NSPersistentCloudKitContainer with a plain
//  NSPersistentContainer (single SQLite store) plus hand-rolled CKFetchDatabaseChanges /
//  CKModifyRecords operations.  This gives us live foreground sync: when a remote push
//  arrives, we run a fetch immediately rather than waiting for an OS-managed background
//  import window.
//

import Foundation
import SwiftUI
import CoreData
import CloudKit
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@Observable
final class CloudSharingService: @unchecked Sendable {

    // MARK: - Shared singleton
    static var shared: CloudSharingService?

    // MARK: - State (observed by views)

    /// Incremented after every successful CloudKit import so views can react.
    private(set) var sharedStoreVersion: Int = 0
    /// Non-nil when share acceptance fails.
    var shareAcceptError: String?

    /// Rolling in-app log of sync activity, viewable on-device without a debugger attached
    /// (Settings/More > View Sync Log). Mirrors what's sent to NSLog.
    private(set) var diagnosticLog: [String] = []

    // MARK: - Private

    let persistentContainer: NSPersistentContainer
    private let ckContainer = CKContainer(identifier: "iCloud.EstraDOS.Home-Maintainer")
    private var contextSaveObserver: NSObjectProtocol?
    // Set true while importing CloudKit records into viewContext to suppress the
    // outbound-upload observer (prevents echo-looping imported records back to CloudKit).
    private var isImportingFromCloudKit = false

    // Entities that participate in CloudKit sync.
    private static let syncedEntityNames: Set<String> = [
        "Home", "MaintenanceTask", "MaintenanceRecord",
        "Appliance", "ServiceProvider", "RepairProject",
        "DocumentSection", "HomeDocument",
        "ChatConversation", "ChatMessageData", "ChatImageData", "UserMemory"
    ]

    /// Entities that always sync to the private "personal" zone (never shared with home
    /// co-owners), regardless of which home they're associated with.
    private static let personalEntityNames: Set<String> = [
        "ChatConversation", "ChatMessageData", "ChatImageData", "UserMemory"
    ]

    /// Fields stored via CKRecord.encryptedValues (CloudKit's built-in field-level encryption,
    /// keyed by the user's iCloud-protected data — unreadable outside their own account/devices).
    private static let encryptedFieldsByEntity: [String: Set<String>] = [
        "ChatMessageData": ["content"],
        "UserMemory": ["content"],
    ]

    // MARK: - Convenience accessor

    var viewContext: NSManagedObjectContext { persistentContainer.viewContext }

    /// Logs to both NSLog (for Console.app/cable debugging) and the in-app diagnostic log
    /// (for on-device debugging with no Mac attached). Safe to call from any thread.
    private func log(_ message: String) {
        NSLog(message)
        DispatchQueue.main.async {
            self.diagnosticLog.append(message)
            if self.diagnosticLog.count > 300 {
                self.diagnosticLog.removeFirst(self.diagnosticLog.count - 300)
            }
        }
    }

    func clearDiagnosticLog() { diagnosticLog.removeAll() }

    // MARK: - Init

    init(container: NSPersistentContainer) {
        self.persistentContainer = container
        setupContextSaveObserver()
        Task { await setupSubscriptionsIfNeeded() }
    }

    // MARK: - Container factory

    static func makeContainer() -> NSPersistentContainer {
        let model = AppDataModel.buildModel()
        let container = NSPersistentContainer(name: "HomeMaintainer", managedObjectModel: model)
        let baseURL = NSPersistentContainer.defaultDirectoryURL()

        // Migration: delete the old two-store shared SQLite file (no longer used).
        let sharedURL = baseURL.appendingPathComponent("HomeMaintainerShared.sqlite")
        if FileManager.default.fileExists(atPath: sharedURL.path) {
            try? FileManager.default.removeItem(at: sharedURL)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: sharedURL.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: sharedURL.path + "-shm"))
            NSLog("[CloudSharingService] Deleted old shared store")
        }

        let privateURL = baseURL.appendingPathComponent("HomeMaintainer.sqlite")

        // Pre-flight compatibility check — intentionally does NOT use migration options.
        // NSInferMappingModelAutomaticallyOption with a programmatically-built (unversioned)
        // model can make Core Data internally synthesize a second, separately-registered copy
        // of the model mid-migration, causing "Multiple NSEntityDescriptions claim the
        // NSManagedObject subclass 'X'" crashes on the very next fetch. Every synced entity
        // already has CloudKit as its durable source of truth, so on ANY schema mismatch —
        // even a purely additive one — we destroy the local store outright and let CloudKit
        // resync repopulate it, rather than risk that migration path at all.
        if FileManager.default.fileExists(atPath: privateURL.path) {
            let probe = NSPersistentStoreCoordinator(managedObjectModel: model)
            if (try? probe.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil,
                                              at: privateURL, options: nil)) == nil {
                NSLog("⚠️ Destroying incompatible CoreData store: \(privateURL.lastPathComponent)")
                try? probe.destroyPersistentStore(at: privateURL, ofType: NSSQLiteStoreType, options: nil)
                // The CloudKit change tokens live in UserDefaults, independent of the SQLite file —
                // destroying the store without also clearing them leaves the fresh, empty store
                // pointing at a token that tells CloudKit "nothing's changed," so previously-synced
                // data (e.g. existing Homes) never gets re-fetched. Clear them so the next sync is
                // a full historical fetch of every zone, repopulating the store as intended.
                clearCloudKitSyncTokens()
            }
        }

        // No migration options here either — the probe above guarantees the store is either
        // already an exact match (opens directly, no migration machinery invoked) or has
        // already been destroyed (creates fresh).
        let desc = NSPersistentStoreDescription(url: privateURL)
        container.persistentStoreDescriptions = [desc]

        UserDefaults.standard.removeObject(forKey: "debug_coredata_error")
        container.loadPersistentStores { _, error in
            if let error {
                NSLog("❌ CoreData load error: \(error)")
                UserDefaults.standard.set(error.localizedDescription, forKey: "debug_coredata_error")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return container
    }

    // MARK: - Outgoing sync (viewContext save → CloudKit upload)

    private func setupContextSaveObserver() {
        contextSaveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: persistentContainer.viewContext,
            queue: nil
        ) { [weak self] notification in
            self?.handleViewContextSave(notification)
        }
    }

    /// Runs synchronously, on whatever thread/queue triggered the save — viewContext is
    /// main-queue-confined, so its NSManagedObject instances are only safe to touch here,
    /// before any thread hop. Builds plain-value CKRecords/UUIDs and hands off only those
    /// to an async Task for the actual network I/O.
    private func handleViewContextSave(_ notification: Notification) {
        // Suppress uploads while we're importing records from CloudKit to avoid echo loops.
        guard !isImportingFromCloudKit else { return }

        let inserted = (notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? [])
            .filter { Self.syncedEntityNames.contains($0.entity.name ?? "") }
        let updated = (notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? [])
            .filter { Self.syncedEntityNames.contains($0.entity.name ?? "") }
        let deleted = (notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> ?? [])
            .filter { Self.syncedEntityNames.contains($0.entity.name ?? "") }

        guard !inserted.isEmpty || !updated.isEmpty || !deleted.isEmpty else { return }
        log("[handleViewContextSave] inserted=\(inserted.count) updated=\(updated.count) deleted=\(deleted.count)")

        let newHomeIDs = inserted.compactMap { $0.entity.name == "Home" ? $0.value(forKey: "id") as? UUID : nil }
        let needsPersonalZone = inserted.contains { Self.personalEntityNames.contains($0.entity.name ?? "") }

        var byZone: [CKRecordZone.ID: (db: CKDatabase, records: [CKRecord])] = [:]
        for obj in Array(inserted) + Array(updated) {
            guard let (zoneID, db) = cloudKitContext(forObject: obj),
                  let record = makeCKRecord(for: obj, zoneID: zoneID) else { continue }
            byZone[zoneID, default: (db, [])].records.append(record)
        }

        var deletions: [(id: UUID, zoneID: CKRecordZone.ID, db: CKDatabase)] = []
        for obj in deleted {
            if let id = obj.value(forKey: "id") as? UUID,
               let (zoneID, db) = cloudKitContext(forObject: obj) {
                deletions.append((id: id, zoneID: zoneID, db: db))
            }
        }

        Task {
            // Zones must exist before records can be saved into them.
            for homeID in newHomeIDs {
                await createZoneIfNeeded(homeID: homeID)
            }
            if needsPersonalZone {
                await createPersonalZoneIfNeeded()
            }
            await withTaskGroup(of: Void.self) { group in
                for (db, records) in byZone.values {
                    group.addTask { await self.saveRecords(records, to: db) }
                }
            }
            for d in deletions {
                await deleteRecord(id: d.id, zoneID: d.zoneID, in: d.db)
            }
        }
    }

    // MARK: - Incoming sync (push → fetch → CoreData upsert)

    /// Call from AppDelegate.didReceiveRemoteNotification.
    func handleRemoteNotification() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchDatabaseChanges(in: self.ckContainer.privateCloudDatabase,
                                                            tokenKey: TokenKey.privateDB) }
            group.addTask { await self.fetchDatabaseChanges(in: self.ckContainer.sharedCloudDatabase,
                                                            tokenKey: TokenKey.sharedDB) }
        }
    }

    private func fetchDatabaseChanges(in database: CKDatabase, tokenKey: String) async {
        var changedZones: [CKRecordZone.ID] = []
        var deletedZones: [CKRecordZone.ID] = []

        let op = CKFetchDatabaseChangesOperation(previousServerChangeToken: loadToken(key: tokenKey))
        op.recordZoneWithIDChangedBlock  = { changedZones.append($0) }
        op.recordZoneWithIDWasDeletedBlock = { deletedZones.append($0) }
        op.fetchDatabaseChangesResultBlock = { [weak self] result in
            switch result {
            case .success(let (token, _)): self?.saveToken(token, key: tokenKey)
            case .failure(let error): self?.log("[CK] fetchDatabaseChanges (\(tokenKey)) FAILED: \(error)")
            }
        }
        await withCheckedContinuation { cont in
            op.completionBlock = { cont.resume() }
            database.add(op)
        }

        if !changedZones.isEmpty {
            await fetchZoneChanges(zoneIDs: changedZones, in: database)
        }
        for zoneID in deletedZones {
            await deleteAllLocalRecords(in: zoneID)
        }
    }

    private func fetchZoneChanges(zoneIDs: [CKRecordZone.ID], in database: CKDatabase) async {
        var configs: [CKRecordZone.ID: CKFetchRecordZoneChangesOperation.ZoneConfiguration] = [:]
        for id in zoneIDs {
            let cfg = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            cfg.previousServerChangeToken = loadToken(key: TokenKey.zone(id))
            configs[id] = cfg
        }

        var toUpsert: [CKRecord] = []
        var toDelete: [CKRecord.ID] = []
        var newTokens: [CKRecordZone.ID: CKServerChangeToken] = [:]

        let op = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs,
                                                    configurationsByRecordZoneID: configs)
        op.recordWasChangedBlock       = { recordID, result in
            switch result {
            case .success(let r): toUpsert.append(r)
            case .failure(let error): self.log("[CK] fetchZoneChanges record=\(recordID.recordName) FAILED: \(error)")
            }
        }
        op.recordWithIDWasDeletedBlock = { id, _ in toDelete.append(id) }
        op.recordZoneFetchResultBlock  = { zoneID, result in
            switch result {
            case .success(let (token, _, _)):
                self.log("[CK] fetchZoneChanges zone=\(zoneID.zoneName) owner=\(zoneID.ownerName) — OK")
                newTokens[zoneID] = token
            case .failure(let error):
                self.log("[CK] fetchZoneChanges zone=\(zoneID.zoneName) owner=\(zoneID.ownerName) — FAILED: \(error)")
            }
        }
        await withCheckedContinuation { cont in
            op.completionBlock = { cont.resume() }
            database.add(op)
        }

        for (zoneID, token) in newTokens { saveToken(token, key: TokenKey.zone(zoneID)) }

        if !toUpsert.isEmpty || !toDelete.isEmpty {
            await applyImportedChanges(upsert: toUpsert, delete: toDelete)
        }
    }

    // MARK: - CoreData upsert from CKRecords

    private func applyImportedChanges(upsert: [CKRecord], delete: [CKRecord.ID]) async {
        log("[applyImportedChanges] \(upsert.count) upserts, \(delete.count) deletes — types: \(upsert.map { $0.recordType })")

        // Import directly into viewContext so changes are immediately visible to @FetchRequest
        // without depending on the bgCtx→viewContext merge path, which can silently fail when
        // the background context is a sibling (not a parent) of viewContext.
        let ctx = persistentContainer.viewContext

        isImportingFromCloudKit = true
        await ctx.perform {
            for record in upsert {
                guard Self.syncedEntityNames.contains(record.recordType),
                      let idStr = record["id"] as? String, let id = UUID(uuidString: idStr) else {
                    continue
                }

                let fetch = NSFetchRequest<NSManagedObject>(entityName: record.recordType)
                fetch.predicate = NSPredicate(format: "id == %@", id as NSUUID)
                fetch.fetchLimit = 1
                let obj = (try? ctx.fetch(fetch).first)
                    ?? NSEntityDescription.insertNewObject(forEntityName: record.recordType, into: ctx)

                let encryptedFields = Self.encryptedFieldsByEntity[record.recordType] ?? []
                for (key, attr) in obj.entity.attributesByName {
                    let raw: Any? = encryptedFields.contains(key) ? record.encryptedValues[key] : record[key]
                    if let raw {
                        obj.setValue(Self.coreDataValue(raw, for: attr), forKey: key)
                    } else if attr.isOptional {
                        obj.setValue(nil, forKey: key)
                    }
                }

                self.restoreRelationships(obj: obj, record: record, in: ctx)
            }

            for recordID in delete {
                guard let id = UUID(uuidString: recordID.recordName) else { continue }
                for entityName in Self.syncedEntityNames {
                    let fetch = NSFetchRequest<NSManagedObject>(entityName: entityName)
                    fetch.predicate = NSPredicate(format: "id == %@", id as NSUUID)
                    fetch.fetchLimit = 1
                    if let obj = try? ctx.fetch(fetch).first { ctx.delete(obj) }
                }
            }

            do {
                try ctx.save()
                self.log("[applyImportedChanges] save OK")
            } catch {
                self.log("[applyImportedChanges] save FAILED: \(error)")
            }
        }
        isImportingFromCloudKit = false

        await MainActor.run { sharedStoreVersion += 1 }
    }

    private func restoreRelationships(obj: NSManagedObject, record: CKRecord, in ctx: NSManagedObjectContext) {
        switch obj.entity.name {
        case "MaintenanceTask", "Appliance", "ServiceProvider", "RepairProject", "DocumentSection", "HomeDocument":
            if let homeIDStr = record["homeIDString"] as? String,
               let homeID = UUID(uuidString: homeIDStr) {
                let f = NSFetchRequest<NSManagedObject>(entityName: "Home")
                f.predicate = NSPredicate(format: "id == %@", homeID as NSUUID)
                f.fetchLimit = 1
                if let home = try? ctx.fetch(f).first { obj.setValue(home, forKey: "home") }
            }
        case "MaintenanceRecord":
            if let taskIDStr = record["taskIDString"] as? String,
               let taskID = UUID(uuidString: taskIDStr) {
                let f = NSFetchRequest<NSManagedObject>(entityName: "MaintenanceTask")
                f.predicate = NSPredicate(format: "id == %@", taskID as NSUUID)
                f.fetchLimit = 1
                if let task = try? ctx.fetch(f).first { obj.setValue(task, forKey: "task") }
            }
        case "ChatMessageData":
            if let convIDStr = record["conversationIDString"] as? String,
               let convID = UUID(uuidString: convIDStr) {
                let f = NSFetchRequest<NSManagedObject>(entityName: "ChatConversation")
                f.predicate = NSPredicate(format: "id == %@", convID as NSUUID)
                f.fetchLimit = 1
                if let conv = try? ctx.fetch(f).first { obj.setValue(conv, forKey: "conversation") }
            }
        case "ChatImageData":
            if let msgIDStr = record["messageIDString"] as? String,
               let msgID = UUID(uuidString: msgIDStr) {
                let f = NSFetchRequest<NSManagedObject>(entityName: "ChatMessageData")
                f.predicate = NSPredicate(format: "id == %@", msgID as NSUUID)
                f.fetchLimit = 1
                if let msg = try? ctx.fetch(f).first { obj.setValue(msg, forKey: "message") }
            }
        default:
            break
        }
    }

    // MARK: - Zone deletion

    private func deleteAllLocalRecords(in zoneID: CKRecordZone.ID) async {
        guard zoneID.zoneName.hasPrefix("home-"),
              let homeID = UUID(uuidString: String(zoneID.zoneName.dropFirst(5))) else { return }

        let bgCtx = persistentContainer.newBackgroundContext()
        await bgCtx.perform {
            let homeIDStr = homeID.uuidString
            let withHomeID: Set<String> = ["MaintenanceTask", "Appliance", "ServiceProvider",
                                           "RepairProject", "DocumentSection", "HomeDocument"]
            for name in withHomeID {
                let f = NSFetchRequest<NSManagedObject>(entityName: name)
                f.predicate = NSPredicate(format: "homeIDString == %@", homeIDStr)
                (try? bgCtx.fetch(f))?.forEach { bgCtx.delete($0) }
            }
            let hf = NSFetchRequest<NSManagedObject>(entityName: "Home")
            hf.predicate = NSPredicate(format: "id == %@", homeID as NSUUID)
            if let h = try? bgCtx.fetch(hf).first { bgCtx.delete(h) }
            try? bgCtx.save()
        }
        await MainActor.run { sharedStoreVersion += 1 }
    }

    // MARK: - Upload helpers

    private func cloudKitContext(forObject obj: NSManagedObject) -> (CKRecordZone.ID, CKDatabase)? {
        guard let entityName = obj.entity.name else { return nil }
        if Self.personalEntityNames.contains(entityName) {
            return (personalZoneID, ckContainer.privateCloudDatabase)
        }
        if entityName == "Home" {
            guard let homeID = obj.value(forKey: "id") as? UUID else { return nil }
            return cloudKitContext(forHomeID: homeID.uuidString)
        }
        if let homeIDStr = obj.value(forKey: "homeIDString") as? String {
            return cloudKitContext(forHomeID: homeIDStr)
        }
        return nil
    }

    /// Fixed per-account zone for chat history + AI memory — private database only, never
    /// shared with home co-owners regardless of which home a conversation is associated with.
    private var personalZoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "personal", ownerName: CKCurrentUserDefaultName)
    }

    private func createPersonalZoneIfNeeded() async {
        do {
            _ = try await ckContainer.privateCloudDatabase.save(CKRecordZone(zoneID: personalZoneID))
        } catch {
            log("[CK] createPersonalZoneIfNeeded FAILED: \(error)")
        }
    }

    private func cloudKitContext(forHomeID homeIDString: String) -> (CKRecordZone.ID, CKDatabase)? {
        guard let homeID = UUID(uuidString: homeIDString) else { return nil }
        if let sharedZone = loadSharedZoneID(for: homeID) {
            return (sharedZone, ckContainer.sharedCloudDatabase)
        }
        let zone = CKRecordZone.ID(zoneName: "home-\(homeID.uuidString)", ownerName: CKCurrentUserDefaultName)
        return (zone, ckContainer.privateCloudDatabase)
    }

    private func createZoneIfNeeded(homeID: UUID) async {
        let zoneID = CKRecordZone.ID(zoneName: "home-\(homeID.uuidString)", ownerName: CKCurrentUserDefaultName)
        do {
            _ = try await ckContainer.privateCloudDatabase.save(CKRecordZone(zoneID: zoneID))
        } catch {
            log("[CK] createZoneIfNeeded FAILED for home=\(homeID): \(error)")
        }
    }

    private func makeCKRecord(for obj: NSManagedObject, zoneID: CKRecordZone.ID) -> CKRecord? {
        guard let id = obj.value(forKey: "id") as? UUID,
              let entityName = obj.entity.name else { return nil }
        let record = CKRecord(recordType: entityName,
                              recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zoneID))
        let encryptedFields = Self.encryptedFieldsByEntity[entityName] ?? []
        for (key, attr) in obj.entity.attributesByName {
            guard let raw = obj.value(forKey: key), let value = Self.ckValue(raw, for: attr) else { continue }
            if encryptedFields.contains(key) {
                record.encryptedValues[key] = value
            } else {
                record[key] = value
            }
        }
        return record
    }

    private func saveRecords(_ records: [CKRecord], to database: CKDatabase) async {
        guard !records.isEmpty else { return }
        let zoneName = records.first?.recordID.zoneID.zoneName ?? "?"
        let types = records.map { $0.recordType }
        let op = CKModifyRecordsOperation(recordsToSave: records)
        op.savePolicy = .allKeys
        op.isAtomic = false
        op.perRecordSaveBlock = { recordID, result in
            if case .failure(let error) = result {
                self.log("[CK] saveRecords FAILED for record=\(recordID.recordName) zone=\(recordID.zoneID.zoneName): \(error)")
            }
        }
        await withCheckedContinuation { cont in
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    self.log("[CK] saveRecords OK — \(records.count) record(s) \(types) to zone=\(zoneName)")
                case .failure(let error):
                    self.log("[CK] saveRecords operation FAILED: \(error)")
                }
                cont.resume()
            }
            database.add(op)
        }
    }

    private func deleteRecord(id: UUID, zoneID: CKRecordZone.ID, in database: CKDatabase) async {
        let op = CKModifyRecordsOperation(recordsToSave: nil,
                                          recordIDsToDelete: [CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)])
        await withCheckedContinuation { cont in
            op.completionBlock = { cont.resume() }
            database.add(op)
        }
    }

    // MARK: - Type mapping (NSManagedObject ↔ CKRecord)

    private static func ckValue(_ raw: Any, for attr: NSAttributeDescription) -> CKRecordValueProtocol? {
        switch attr.attributeType {
        case .UUIDAttributeType:
            return (raw as? UUID)?.uuidString
        case .booleanAttributeType:
            return (raw as? Bool).map { NSNumber(value: $0 ? 1 : 0) }
        case .integer32AttributeType:
            return (raw as? Int32).map { NSNumber(value: Int($0)) }
        case .binaryDataAttributeType:
            guard let data = raw as? Data, !data.isEmpty else { return nil }
            if attr.allowsExternalBinaryDataStorage {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try? data.write(to: url)
                return CKAsset(fileURL: url)
            }
            return data as NSData
        default:
            return raw as? CKRecordValueProtocol
        }
    }

    private static func coreDataValue(_ raw: Any, for attr: NSAttributeDescription) -> Any? {
        switch attr.attributeType {
        case .UUIDAttributeType:
            return (raw as? String).flatMap(UUID.init(uuidString:))
        case .booleanAttributeType:
            return (raw as? NSNumber).map { $0.intValue != 0 }
        case .integer32AttributeType:
            return (raw as? NSNumber).map { Int32($0.intValue) }
        case .binaryDataAttributeType:
            if let asset = raw as? CKAsset, let url = asset.fileURL {
                return try? Data(contentsOf: url)
            }
            return raw as? Data
        default:
            return raw
        }
    }

    // MARK: - Subscriptions

    func setupSubscriptionsIfNeeded() async {
        if !UserDefaults.standard.bool(forKey: "ck_sub_private_v1") {
            let sub = CKDatabaseSubscription(subscriptionID: "home-maintainer-private-v1")
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            sub.notificationInfo = info
            if (try? await ckContainer.privateCloudDatabase.save(sub)) != nil {
                UserDefaults.standard.set(true, forKey: "ck_sub_private_v1")
            }
        }
        if !UserDefaults.standard.bool(forKey: "ck_sub_shared_v1") {
            let sub = CKDatabaseSubscription(subscriptionID: "home-maintainer-shared-v1")
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            sub.notificationInfo = info
            if (try? await ckContainer.sharedCloudDatabase.save(sub)) != nil {
                UserDefaults.standard.set(true, forKey: "ck_sub_shared_v1")
            }
        }
    }

    // MARK: - Initial upload (first launch after migration from NSPersistentCloudKitContainer)

    @MainActor
    func performInitialUploadIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: "directCloudKitMigrated_v1") else { return }
        log("[CloudSharingService] First launch — uploading all local data to direct CloudKit zones")

        let ctx = persistentContainer.viewContext

        let homeFetch = NSFetchRequest<NSManagedObject>(entityName: "Home")
        let homes = (try? ctx.fetch(homeFetch)) ?? []
        for h in homes {
            if let homeID = h.value(forKey: "id") as? UUID {
                await createZoneIfNeeded(homeID: homeID)
            }
        }

        var privateRecords: [CKRecord] = []
        var sharedRecords: [CKRecord] = []
        for entityName in Self.syncedEntityNames {
            let f = NSFetchRequest<NSManagedObject>(entityName: entityName)
            let objs = (try? ctx.fetch(f)) ?? []
            for obj in objs {
                guard let (zoneID, db) = cloudKitContext(forObject: obj),
                      let record = makeCKRecord(for: obj, zoneID: zoneID) else { continue }
                if db === ckContainer.privateCloudDatabase {
                    privateRecords.append(record)
                } else {
                    sharedRecords.append(record)
                }
            }
        }

        let batchSize = 400
        for start in stride(from: 0, to: privateRecords.count, by: batchSize) {
            let end = min(start + batchSize, privateRecords.count)
            await saveRecords(Array(privateRecords[start..<end]), to: ckContainer.privateCloudDatabase)
        }
        for start in stride(from: 0, to: sharedRecords.count, by: batchSize) {
            let end = min(start + batchSize, sharedRecords.count)
            await saveRecords(Array(sharedRecords[start..<end]), to: ckContainer.sharedCloudDatabase)
        }

        // Pull down any remote changes (gets shared homes on a fresh device)
        await handleRemoteNotification()

        UserDefaults.standard.set(true, forKey: "directCloudKitMigrated_v1")
        log("[CloudSharingService] Initial upload done — \(privateRecords.count) private + \(sharedRecords.count) shared")
    }

    // MARK: - Personal data migration (chat history + AI memory → CloudKit personal zone)

    /// One-time migration, separate from performInitialUploadIfNeeded above: that flag was
    /// already set for existing users before chat/memory entities existed in syncedEntityNames,
    /// so it won't re-run to pick these up. This uploads any local chat history to the new
    /// personal zone, and pulls the legacy Firestore aiMemory string into local UserMemory
    /// (clearing it server-side afterward) so nothing is lost in the switch.
    @MainActor
    func migratePersonalDataIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: "personalZoneMigrated_v1") else { return }
        log("[CloudSharingService] Migrating chat history + memory to personal CloudKit zone")

        let ctx = persistentContainer.viewContext

        // Don't mark this migration done until we've actually had a signed-in session to check
        // Firestore against — otherwise a launch that races ahead of sign-in permanently skips
        // the legacy aiMemory migration, since this flag never gets a second chance to run.
        guard let uid = Auth.auth().currentUser?.uid else {
            log("[CloudSharingService] Not signed in yet — will retry personal data migration on next launch")
            return
        }

        let doc = try? await Firestore.firestore().collection("users").document(uid).getDocument()
        if let legacyMemory = doc?.data()?["aiMemory"] as? String, !legacyMemory.isEmpty {
            let memory = UserMemory.fetchOrCreate(in: ctx)
            if (memory.content ?? "").isEmpty {
                memory.content = legacyMemory
                memory.updatedAt = Date()
                try? ctx.save()
            }
            _ = try? await Functions.functions().httpsCallable("clearMigratedMemory").call([:] as [String: Any])
            log("[CloudSharingService] Migrated legacy aiMemory from Firestore, cleared remote copy")
        }

        await createPersonalZoneIfNeeded()

        var records: [CKRecord] = []
        for entityName in Self.personalEntityNames {
            let f = NSFetchRequest<NSManagedObject>(entityName: entityName)
            let objs = (try? ctx.fetch(f)) ?? []
            for obj in objs {
                guard let (zoneID, _) = cloudKitContext(forObject: obj),
                      let record = makeCKRecord(for: obj, zoneID: zoneID) else { continue }
                records.append(record)
            }
        }

        let batchSize = 400
        for start in stride(from: 0, to: records.count, by: batchSize) {
            let end = min(start + batchSize, records.count)
            await saveRecords(Array(records[start..<end]), to: ckContainer.privateCloudDatabase)
        }

        UserDefaults.standard.set(true, forKey: "personalZoneMigrated_v1")
        log("[CloudSharingService] Personal data migration done — \(records.count) record(s)")
    }

    // MARK: - One-time recovery from the build 73 stale-token bug

    /// Build 73's schema change (adding the personal-zone entities above) triggered
    /// makeContainer()'s store-destroy safety valve, but at the time it didn't clear the
    /// CloudKit change tokens — leaving affected installs with an empty local store that
    /// believed itself fully synced, silently hiding previously-synced Homes and other data.
    /// This runs once to clear those stale tokens and force an immediate full resync, so
    /// already-affected devices self-heal on the next launch without needing a reinstall.
    @MainActor
    func recoverStaleCloudKitTokensIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: "staleTokenRecovery_build73_v1") else { return }
        log("[CloudSharingService] Recovering from build 73 stale-token bug — forcing full resync")

        Self.clearCloudKitSyncTokens()
        await handleRemoteNotification()

        UserDefaults.standard.set(true, forKey: "staleTokenRecovery_build73_v1")
        log("[CloudSharingService] Stale-token recovery done")
    }

    // MARK: - Sharing

    func shareLink(for home: Home, completion: @escaping (Result<URL, Error>) -> Void) {
        Task {
            do {
                let (share, _) = try await createOrFetchShare(for: home)
                guard let url = share.url else {
                    await MainActor.run { completion(.failure(SharingError.shareURLUnavailable)) }
                    return
                }
                await MainActor.run { completion(.success(url)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    private func createOrFetchShare(for home: Home) async throws -> (CKShare, CKContainer) {
        let zoneID = CKRecordZone.ID(zoneName: "home-\(home.id.uuidString)", ownerName: CKCurrentUserDefaultName)
        let db = ckContainer.privateCloudDatabase

        // Try fetching an existing zone-wide share.
        let shareRecordID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        if let existing = try? await db.record(for: shareRecordID) as? CKShare {
            if existing.publicPermission != .readWrite {
                existing.publicPermission = .readWrite
                existing[CKShare.SystemFieldKey.title] = home.name as CKRecordValue
                try await modifySingleRecord(existing, in: db)
            }
            return (existing, ckContainer)
        }

        // Zone must exist before we create a share.
        await createZoneIfNeeded(homeID: home.id)

        let share = CKShare(recordZoneID: zoneID)
        share.publicPermission = .readWrite
        share[CKShare.SystemFieldKey.title] = home.name as CKRecordValue
        try await modifySingleRecord(share, in: db)
        return (share, ckContainer)
    }

    private func modifySingleRecord(_ record: CKRecord, in database: CKDatabase) async throws {
        let op = CKModifyRecordsOperation(recordsToSave: [record])
        op.savePolicy = .allKeys
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            database.add(op)
        }
    }

    func acceptShare(metadata: CKShare.Metadata) {
        Task {
            do {
                try await ckContainer.accept(metadata)

                let metadataZoneID = metadata.share.recordID.zoneID
                log("[acceptShare] accepted — zoneName=\(metadataZoneID.zoneName) ownerName=\(metadataZoneID.ownerName)")

                // Store zone ID keyed by home UUID so future writes route to the shared database.
                var homeID: UUID?
                if metadataZoneID.zoneName.hasPrefix("home-"),
                   let id = UUID(uuidString: String(metadataZoneID.zoneName.dropFirst(5))) {
                    homeID = id
                    saveSharedZoneID(metadataZoneID, for: id)
                    log("[acceptShare] stored sharedZone for home \(id)")
                }

                // Ensure a subscription exists for the shared database.
                UserDefaults.standard.set(false, forKey: "ck_sub_shared_v1")
                await setupSubscriptionsIfNeeded()

                // A freshly-accepted share is often not yet queryable on Apple's servers —
                // CKFetchDatabaseChangesOperation/CKFetchRecordZoneChangesOperation can both
                // return empty for a few seconds after accept() succeeds. Retry with backoff
                // until the Home record actually lands instead of giving up after one attempt.
                for attempt in 0..<4 {
                    if attempt > 0 {
                        log("[acceptShare] home not found yet, retrying in \(attempt * 2)s (attempt \(attempt + 1)/4)")
                        try? await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                    }

                    // Reset the shared-DB token so CKFetchDatabaseChangesOperation does a full
                    // sync, which gives us zone IDs with properly-resolved ownerNames (not "__defaultOwner__").
                    UserDefaults.standard.removeObject(forKey: TokenKey.sharedDB)
                    log("[acceptShare] fetching shared DB changes (full sync)…")
                    await fetchDatabaseChanges(in: ckContainer.sharedCloudDatabase, tokenKey: TokenKey.sharedDB)

                    // Also fetch using the metadata zone ID directly. If the fetch above already
                    // imported the records, this is a no-op (server change token is now stored,
                    // so the operation returns nothing new). If it missed the zone, this catches it.
                    log("[acceptShare] direct zone fetch — zoneName=\(metadataZoneID.zoneName)")
                    await fetchZoneChanges(zoneIDs: [metadataZoneID], in: ckContainer.sharedCloudDatabase)

                    if let homeID, findHomeManagedObject(id: homeID) != nil {
                        log("[acceptShare] home \(homeID) confirmed present after attempt \(attempt + 1)")
                        break
                    }
                }

                await MainActor.run { sharedStoreVersion += 1 }
                log("[acceptShare] done — sharedStoreVersion incremented")

            } catch {
                log("[acceptShare] ERROR: \(error)")
                await MainActor.run {
                    if error.localizedDescription.lowercased().contains("owner") {
                        shareAcceptError = "You're already the owner of this home — it's already in your app."
                    } else {
                        shareAcceptError = "Could not accept the home invitation.\n\n\(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func removeSharedHome(_ home: Home) {
        let ctx = persistentContainer.viewContext
        if let obj = try? findManagedObject(id: home.id, entityName: "Home", in: ctx) {
            ctx.delete(obj)
            try? ctx.save()
        }
        UserDefaults.standard.removeObject(forKey: sharedZoneIDKey(for: home.id))
    }

    // MARK: - Helpers

    /// Returns true when this device is a participant (not the owner) for the given home.
    /// The test: a stored shared zone ID means the home arrived via CKShare acceptance.
    func isParticipant(in home: Home) -> Bool {
        loadSharedZoneID(for: home.id) != nil
    }

    func findHomeManagedObject(id: UUID) -> NSManagedObject? {
        try? findManagedObject(id: id, entityName: "Home", in: persistentContainer.viewContext)
    }

    private func findManagedObject(id: UUID, entityName: String, in ctx: NSManagedObjectContext) throws -> NSManagedObject? {
        let r = NSFetchRequest<NSManagedObject>(entityName: entityName)
        r.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        r.fetchLimit = 1
        return try ctx.fetch(r).first
    }

    func save() {
        let ctx = persistentContainer.viewContext
        guard ctx.hasChanges else { return }
        try? ctx.save()
    }

    // MARK: - Token and zone ID storage

    private enum TokenKey {
        static let privateDB = "ck_token_privateDB_v1"
        static let sharedDB  = "ck_token_sharedDB_v1"
        static func zone(_ id: CKRecordZone.ID) -> String { "ck_zone_\(id.ownerName)_\(id.zoneName)" }
    }

    /// Clears every cached CloudKit change token (database-level and per-zone), forcing the next
    /// fetch to be a full historical one rather than "what's changed since last time." Needed
    /// whenever the local CoreData store is discarded, since these tokens live in UserDefaults
    /// independent of the SQLite file and would otherwise survive a store wipe untouched.
    static func clearCloudKitSyncTokens() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("ck_token_") || key.hasPrefix("ck_zone_") {
            defaults.removeObject(forKey: key)
        }
    }

    private func sharedZoneIDKey(for homeID: UUID) -> String { "ck_sharedZone_\(homeID.uuidString)" }

    private func loadToken(key: String) -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveToken(_ token: CKServerChangeToken, key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func loadSharedZoneID(for homeID: UUID) -> CKRecordZone.ID? {
        guard let data = UserDefaults.standard.data(forKey: sharedZoneIDKey(for: homeID)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecordZone.ID.self, from: data)
    }

    private func saveSharedZoneID(_ zoneID: CKRecordZone.ID, for homeID: UUID) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: zoneID, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: sharedZoneIDKey(for: homeID))
    }

    deinit {
        if let obs = contextSaveObserver { NotificationCenter.default.removeObserver(obs) }
    }

    // MARK: - Backward-compatibility stubs (single-store model — concepts no longer apply)

    /// Always false: with a single CoreData store there is no separate "shared store".
    func isInSharedStore(entityName: String, id: UUID) -> Bool { false }

    /// Always false: share state is tracked by zone IDs, not CoreData stores.
    func isOwnedAndShared(homeID: UUID) -> Bool { false }

    /// Alias for save().
    func saveSharedContext() { save() }

    // MARK: - Errors

    enum SharingError: LocalizedError {
        case shareURLUnavailable

        var errorDescription: String? {
            "The share link could not be retrieved. Please try again."
        }
    }
}

// MARK: - UICloudSharingController SwiftUI wrapper (kept for any future UIKit sharing UI)

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
