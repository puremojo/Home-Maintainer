//
//  ServicesHomeExportService.swift
//  Home Maintainer
//

import Foundation
import CoreData

// MARK: - Snapshot types (Codable mirror of the CoreData models)

struct HomeExportData: Codable {
    let version: Int
    let exportedAt: Date
    let home: HomeSnapshot
    let tasks: [TaskSnapshot]
    let appliances: [ApplianceSnapshot]
    let serviceProviders: [ProviderSnapshot]
    let projects: [ProjectSnapshot]
    let documentSections: [DocumentSectionSnapshot]

    init(version: Int, exportedAt: Date, home: HomeSnapshot, tasks: [TaskSnapshot],
         appliances: [ApplianceSnapshot], serviceProviders: [ProviderSnapshot],
         projects: [ProjectSnapshot], documentSections: [DocumentSectionSnapshot] = []) {
        self.version = version
        self.exportedAt = exportedAt
        self.home = home
        self.tasks = tasks
        self.appliances = appliances
        self.serviceProviders = serviceProviders
        self.projects = projects
        self.documentSections = documentSections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        home = try container.decode(HomeSnapshot.self, forKey: .home)
        tasks = try container.decode([TaskSnapshot].self, forKey: .tasks)
        appliances = try container.decode([ApplianceSnapshot].self, forKey: .appliances)
        serviceProviders = try container.decode([ProviderSnapshot].self, forKey: .serviceProviders)
        projects = try container.decode([ProjectSnapshot].self, forKey: .projects)
        documentSections = (try? container.decode([DocumentSectionSnapshot].self, forKey: .documentSections)) ?? []
    }
}

struct HomeSnapshot: Codable {
    let id: UUID
    let name: String
    let address: String
    let createdDate: Date
    let ownerName: String
}

struct TaskSnapshot: Codable {
    let name: String
    let taskDescription: String
    let room: String
    let frequency: TaskFrequency
    let isActive: Bool
    let createdAt: Date
    let lastCompleted: Date?
    let nextDue: Date?
}

struct ApplianceSnapshot: Codable {
    let name: String
    let type: ApplianceType
    let manufacturer: String
    let modelNumber: String
    let purchaseDate: Date?
    let warrantyExpiration: Date?
    let notes: String
    let createdAt: Date
    // Photos excluded from export — they can be large and must be re-added manually.
}

struct ProviderSnapshot: Codable {
    let name: String
    let category: ServiceCategory
    let phoneNumber: String
    let email: String
    let address: String
    let website: String
    let notes: String
    let isFavorite: Bool
    let rating: Int
    let createdAt: Date
}

struct ProjectSnapshot: Codable {
    let title: String
    let projectDescription: String
    let category: ServiceCategory
    let status: ProjectStatus
    let priority: ProjectPriority
    let notes: String
    let createdAt: Date
}

struct DocumentSectionSnapshot: Codable {
    let name: String
    let sortOrder: Int
    let createdAt: Date
    let documents: [HomeDocumentSnapshot]
}

struct HomeDocumentSnapshot: Codable {
    let title: String
    let attachmentData: Data?
    let attachmentName: String?
    let attachmentContentType: String?
    let createdAt: Date
    // linkedTaskIDs and linkedAppliance are not exported — UUIDs differ per device
}

// MARK: - Service

enum HomeExportService {

    // MARK: Export

    static func export(home: Home) throws -> Data {
        let snapshot = HomeExportData(
            version: 1,
            exportedAt: Date(),
            home: HomeSnapshot(
                id: home.id,
                name: home.name,
                address: home.address,
                createdDate: home.createdDate,
                ownerName: home.ownerName
            ),
            tasks: ((home.tasks as? Set<MaintenanceTask>) ?? []).map { task in
                TaskSnapshot(
                    name: task.name,
                    taskDescription: task.taskDescription,
                    room: task.room,
                    frequency: task.frequency,
                    isActive: task.isActive,
                    createdAt: task.createdAt,
                    lastCompleted: task.lastCompleted,
                    nextDue: task.nextDue
                )
            },
            appliances: ((home.appliances as? Set<Appliance>) ?? []).map { appliance in
                ApplianceSnapshot(
                    name: appliance.name,
                    type: appliance.type,
                    manufacturer: appliance.manufacturer,
                    modelNumber: appliance.modelNumber,
                    purchaseDate: appliance.purchaseDate,
                    warrantyExpiration: appliance.warrantyExpiration,
                    notes: appliance.notes,
                    createdAt: appliance.createdAt
                )
            },
            serviceProviders: ((home.serviceProviders as? Set<ServiceProvider>) ?? []).map { provider in
                ProviderSnapshot(
                    name: provider.name,
                    category: provider.category,
                    phoneNumber: provider.phoneNumber,
                    email: provider.email,
                    address: provider.address,
                    website: provider.website,
                    notes: provider.notes,
                    isFavorite: provider.isFavorite,
                    rating: Int(provider.rating),
                    createdAt: provider.createdAt
                )
            },
            projects: ((home.projects as? Set<RepairProject>) ?? []).map { project in
                ProjectSnapshot(
                    title: project.title,
                    projectDescription: project.projectDescription,
                    category: project.category,
                    status: project.status,
                    priority: project.priority,
                    notes: project.notes,
                    createdAt: project.createdAt
                )
            },
            documentSections: ((home.documentSections as? Set<DocumentSection>) ?? [])
                .sorted(by: { $0.createdAt < $1.createdAt })
                .map { section in
                    DocumentSectionSnapshot(
                        name: section.name,
                        sortOrder: Int(section.sortOrder),
                        createdAt: section.createdAt,
                        documents: ((section.documents as? Set<HomeDocument>) ?? [])
                            .sorted(by: { $0.createdAt < $1.createdAt })
                            .map { doc in
                                HomeDocumentSnapshot(
                                    title: doc.title,
                                    attachmentData: doc.attachmentData,
                                    attachmentName: doc.attachmentName,
                                    attachmentContentType: doc.attachmentContentType,
                                    createdAt: doc.createdAt
                                )
                            }
                    )
                }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(snapshot)
    }

    // MARK: Import

    /// Creates a new Home (with new UUIDs) from exported data and inserts it into the context.
    @discardableResult
    static func importHome(from data: Data, into context: NSManagedObjectContext) throws -> Home {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(HomeExportData.self, from: data)

        let home = Home.make(
            name: snapshot.home.name,
            ownerName: snapshot.home.ownerName,
            address: snapshot.home.address,
            isLocallyCreated: false,  // imported from someone else
            in: context
        )
        home.createdDate = snapshot.home.createdDate

        for t in snapshot.tasks {
            let task = MaintenanceTask.make(
                name: t.name,
                description: t.taskDescription,
                frequency: t.frequency,
                room: t.room,
                in: context
            )
            task.isActive = t.isActive
            task.lastCompleted = t.lastCompleted
            task.nextDue = t.nextDue
            task.home = home
            task.homeIDString = home.id.uuidString
        }

        for a in snapshot.appliances {
            let appliance = Appliance.make(
                name: a.name,
                type: a.type,
                manufacturer: a.manufacturer,
                modelNumber: a.modelNumber,
                in: context
            )
            appliance.purchaseDate = a.purchaseDate
            appliance.warrantyExpiration = a.warrantyExpiration
            appliance.notes = a.notes
            appliance.home = home
            appliance.homeIDString = home.id.uuidString
        }

        for p in snapshot.serviceProviders {
            let provider = ServiceProvider.make(
                name: p.name,
                category: p.category,
                phoneNumber: p.phoneNumber,
                email: p.email,
                in: context
            )
            provider.address = p.address
            provider.website = p.website
            provider.notes = p.notes
            provider.isFavorite = p.isFavorite
            provider.rating = Int32(p.rating)
            provider.home = home
            provider.homeIDString = home.id.uuidString
        }

        for proj in snapshot.projects {
            let project = RepairProject.make(
                title: proj.title,
                description: proj.projectDescription,
                category: proj.category,
                priority: proj.priority,
                in: context
            )
            project.status = proj.status
            project.notes = proj.notes
            project.home = home
            project.homeIDString = home.id.uuidString
        }

        for (i, sec) in snapshot.documentSections.enumerated() {
            let section = DocumentSection.make(name: sec.name, sortOrder: i, in: context)
            section.home = home
            section.homeIDString = home.id.uuidString

            for docSnap in sec.documents {
                let doc = HomeDocument.make(title: docSnap.title, in: context)
                doc.attachmentData = docSnap.attachmentData
                doc.attachmentName = docSnap.attachmentName
                doc.attachmentContentType = docSnap.attachmentContentType
                doc.section = section
                doc.home = home
                doc.homeIDString = home.id.uuidString
                doc.sectionIDString = section.id.uuidString
            }
        }

        try context.save()
        return home
    }

    // MARK: Temp file for sharing

    static func writeTempFile(data: Data, homeName: String) throws -> URL {
        let sanitized = homeName.components(separatedBy: .init(charactersIn: "/\\:*?\"<>|")).joined(separator: "_")
        let fileName = "\(sanitized)_home_export.homemaintainer"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }
}
