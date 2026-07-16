
//
//  ModelsSchema.swift
//  Home Maintainer
//
//  Defines the versioned schema history and migration plan for the SwiftData store.
//  V1 → V2: removes the Home↔ChatConversation relationship (replaced by homeID: UUID?
//  on ChatConversation) so that chat data is excluded from CloudKit zone sharing.
//

import SwiftData
import Foundation

// MARK: - Schema V1  (matches the on-disk store shipped before CloudKit sharing)

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV1.Home.self,
            SchemaV1.ChatConversation.self,
            ChatMessageData.self, ChatImageData.self,
            MaintenanceTask.self, MaintenanceRecord.self,
            Appliance.self, AppliancePhoto.self,
            ServiceProvider.self,
            RepairProject.self, ProductLink.self, ProjectContact.self, Quote.self, Invoice.self,
            DocumentSection.self, HomeDocument.self,
        ]
    }

    @Model final class Home {
        var id: UUID
        var name: String
        var address: String
        var createdDate: Date
        var ownerName: String
        var isLocallyCreated: Bool

        // The relationship being REMOVED in V2
        @Relationship(deleteRule: .cascade, inverse: \SchemaV1.ChatConversation.home)
        var chatConversations: [SchemaV1.ChatConversation]?

        // Unchanged relationships – inverse omitted to avoid Swift type-mismatch (the
        // inverse side still references the current `Home` type, not SchemaV1.Home).
        @Relationship(deleteRule: .cascade) var tasks: [MaintenanceTask]?
        @Relationship(deleteRule: .cascade) var appliances: [Appliance]?
        @Relationship(deleteRule: .cascade) var serviceProviders: [ServiceProvider]?
        @Relationship(deleteRule: .cascade) var projects: [RepairProject]?
        @Relationship(deleteRule: .cascade) var documentSections: [DocumentSection]?
        @Relationship(deleteRule: .cascade) var homeDocuments: [HomeDocument]?

        init(name: String, address: String = "", ownerName: String = "", isLocallyCreated: Bool = true) {
            self.id = UUID()
            self.name = name
            self.address = address
            self.createdDate = Date()
            self.ownerName = ownerName
            self.isLocallyCreated = isLocallyCreated
        }
    }

    @Model final class ChatConversation {
        var id: UUID
        var title: String
        var createdAt: Date
        var lastMessageAt: Date
        @Relationship(deleteRule: .cascade) var messages: [ChatMessageData]?
        var home: SchemaV1.Home?   // removed in V2

        init(title: String = "New Chat") {
            self.id = UUID()
            self.title = title
            self.createdAt = Date()
            self.lastMessageAt = Date()
            self.messages = []
        }
    }
}

// MARK: - Schema V2  (chatConversations removed from Home, homeID added to ChatConversation)

enum SchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Home.self,
            ChatConversation.self, ChatMessageData.self, ChatImageData.self,
            MaintenanceTask.self, MaintenanceRecord.self,
            Appliance.self, AppliancePhoto.self,
            ServiceProvider.self,
            RepairProject.self, ProductLink.self, ProjectContact.self, Quote.self, Invoice.self,
            DocumentSection.self, HomeDocument.self,
        ]
    }
}

// MARK: - Schema V3  (current – CloudKit compliance: attribute defaults + inverse relationships)

enum SchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Home.self,
            ChatConversation.self, ChatMessageData.self, ChatImageData.self,
            MaintenanceTask.self, MaintenanceRecord.self,
            Appliance.self, AppliancePhoto.self,
            ServiceProvider.self,
            RepairProject.self, ProductLink.self, ProjectContact.self, Quote.self, Invoice.self,
            DocumentSection.self, HomeDocument.self,
        ]
    }
}

// MARK: - Migration Plan

enum HomeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self, SchemaV3.self] }
    static var stages: [MigrationStage] { [migrateV1toV2, migrateV2toV3] }

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: { context in
            // Snapshot conversation→home associations before the relationship is dropped.
            let conversations = try context.fetch(FetchDescriptor<SchemaV1.ChatConversation>())
            var map: [String: String] = [:]
            for conv in conversations {
                if let homeID = conv.home?.id {
                    map[conv.id.uuidString] = homeID.uuidString
                }
            }
            if !map.isEmpty {
                UserDefaults.standard.set(map, forKey: "chat_homeID_migration_v1v2")
            }
        },
        didMigrate: { context in
            // Restore the associations on the new homeID attribute.
            guard let map = UserDefaults.standard.dictionary(forKey: "chat_homeID_migration_v1v2")
                    as? [String: String] else { return }
            let conversations = try context.fetch(FetchDescriptor<ChatConversation>())
            for conv in conversations {
                if let str = map[conv.id.uuidString], let uuid = UUID(uuidString: str) {
                    conv.homeID = uuid
                }
            }
            try context.save()
            UserDefaults.standard.removeObject(forKey: "chat_homeID_migration_v1v2")
        }
    )

    static let migrateV2toV3 = MigrationStage.lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)
}
