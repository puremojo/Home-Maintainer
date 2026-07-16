
//
//  ServicesCloudSharingService.swift
//  Home Maintainer
//
//  Manages CloudKit zone sharing for Home objects via NSPersistentCloudKitContainer.
//  The underlying container is captured lazily from the first CloudKit sync event
//  that SwiftData posts after the store loads.
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
            guard self?.persistentCloudKitContainer == nil,
                  let container = notification.object as? NSPersistentCloudKitContainer
            else { return }
            self?.persistentCloudKitContainer = container
            self?.setupDatabaseSubscriptions(container: container)
            #if DEBUG
            DispatchQueue.global(qos: .utility).async {
                do {
                    try container.initializeCloudKitSchema(options: [])
                    print("[CloudSharingService] CloudKit schema initialized")
                } catch {
                    print("[CloudSharingService] initializeCloudKitSchema error: \(error)")
                }
            }
            #endif
        }
    }

    deinit {
        if let observer = eventObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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

    // MARK: - Share a Home

    /// Returns a configured UICloudSharingController for the given home.
    /// Waits up to 15 seconds for the CloudKit container to initialize before giving up.
    /// Calls the completion handler on the main thread with the controller, or an error.
    func sharingController(
        for home: Home,
        from modelContext: ModelContext,
        completion: @escaping (Result<UICloudSharingController, Error>) -> Void
    ) {
        Task { @MainActor in
            // Wait up to 15 s for the container (fires after first CloudKit sync event).
            var ticks = 0
            while persistentCloudKitContainer == nil, ticks < 30 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                ticks += 1
            }

            guard let ckContainer = persistentCloudKitContainer else {
                completion(.failure(SharingError.containerNotReady))
                return
            }

            // Access the underlying NSManagedObjectContext via Mirror.
            guard let nsContext = nsContext(from: modelContext),
                  let homeObject = try? findManagedObject(id: home.id, entityName: "Home", in: nsContext)
            else {
                completion(.failure(SharingError.objectNotFound))
                return
            }

            // Check whether this Home already has a share (synchronous throwing API).
            if let shares = try? ckContainer.fetchShares(matching: [homeObject.objectID]),
               let existingShare = shares[homeObject.objectID] {
                let controller = UICloudSharingController(share: existingShare,
                                                          container: CKContainer(identifier: "iCloud.EstraDOS.Home-Maintainer"))
                controller.availablePermissions = [.allowReadOnly, .allowReadWrite, .allowPublic]
                completion(.success(controller))
            } else {
                createShare(for: homeObject, home: home, container: ckContainer, completion: completion)
            }
        }
    }

    private func createShare(
        for homeObject: NSManagedObject,
        home: Home,
        container: NSPersistentCloudKitContainer,
        completion: @escaping (Result<UICloudSharingController, Error>) -> Void
    ) {
        container.share([homeObject], to: nil) { _, share, ckContainer, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let share, let ckContainer else {
                    completion(.failure(SharingError.shareCreationFailed))
                    return
                }
                share[CKShare.SystemFieldKey.title] = home.name as CKRecordValue
                let controller = UICloudSharingController(share: share, container: ckContainer)
                controller.availablePermissions = [.allowReadOnly, .allowReadWrite, .allowPublic]
                completion(.success(controller))
            }
        }
    }

    // MARK: - Accept an Incoming Share Invitation

    func acceptShare(metadata: CKShare.Metadata) {
        guard let container = persistentCloudKitContainer,
              let store = container.persistentStoreCoordinator.persistentStores.first
        else { return }
        container.acceptShareInvitations(from: [metadata], into: store) { _, error in
            if let error {
                print("[CloudSharingService] acceptShareInvitations error: \(error)")
            }
        }
    }

    // MARK: - Helpers

    private func nsContext(from modelContext: ModelContext) -> NSManagedObjectContext? {
        let mirror = Mirror(reflecting: modelContext)
        for child in mirror.children {
            if let ctx = child.value as? NSManagedObjectContext { return ctx }
        }
        return nil
    }

    private func findManagedObject(
        id: UUID, entityName: String, in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    // MARK: - Errors

    enum SharingError: LocalizedError {
        case containerNotReady
        case objectNotFound
        case shareCreationFailed

        var errorDescription: String? {
            switch self {
            case .containerNotReady:  return "iCloud sync is still initializing. Please try again in a moment."
            case .objectNotFound:     return "Could not find this home in the local database."
            case .shareCreationFailed: return "Failed to create a CloudKit share. Please try again."
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
