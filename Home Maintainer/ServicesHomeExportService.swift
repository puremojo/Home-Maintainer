//
//  ServicesHomeExportService.swift
//  Home Maintainer
//

import Foundation
import SwiftData

// MARK: - Snapshot types (Codable mirror of the SwiftData models)

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
            tasks: (home.tasks ?? []).map { task in
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
            appliances: (home.appliances ?? []).map { appliance in
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
            serviceProviders: (home.serviceProviders ?? []).map { provider in
                ProviderSnapshot(
                    name: provider.name,
                    category: provider.category,
                    phoneNumber: provider.phoneNumber,
                    email: provider.email,
                    address: provider.address,
                    website: provider.website,
                    notes: provider.notes,
                    isFavorite: provider.isFavorite,
                    rating: provider.rating,
                    createdAt: provider.createdAt
                )
            },
            projects: (home.projects ?? []).map { project in
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
            documentSections: (home.documentSections ?? [])
                .sorted(by: { $0.createdAt < $1.createdAt })
                .map { section in
                    DocumentSectionSnapshot(
                        name: section.name,
                        sortOrder: section.sortOrder,
                        createdAt: section.createdAt,
                        documents: (section.documents ?? [])
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
    static func importHome(from data: Data, into context: ModelContext) throws -> Home {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(HomeExportData.self, from: data)

        let home = Home(
            name: snapshot.home.name,
            address: snapshot.home.address,
            ownerName: snapshot.home.ownerName,
            isLocallyCreated: false  // imported from someone else
        )
        home.createdDate = snapshot.home.createdDate
        context.insert(home)

        for t in snapshot.tasks {
            let task = MaintenanceTask(
                name: t.name,
                description: t.taskDescription,
                frequency: t.frequency,
                room: t.room
            )
            task.isActive = t.isActive
            task.lastCompleted = t.lastCompleted
            task.nextDue = t.nextDue
            task.home = home
            task.homeIDString = home.id.uuidString
            context.insert(task)
        }

        for a in snapshot.appliances {
            let appliance = Appliance(
                name: a.name,
                type: a.type,
                manufacturer: a.manufacturer,
                modelNumber: a.modelNumber
            )
            appliance.purchaseDate = a.purchaseDate
            appliance.warrantyExpiration = a.warrantyExpiration
            appliance.notes = a.notes
            appliance.home = home
            appliance.homeIDString = home.id.uuidString
            context.insert(appliance)
        }

        for p in snapshot.serviceProviders {
            let provider = ServiceProvider(
                name: p.name,
                category: p.category,
                phoneNumber: p.phoneNumber,
                email: p.email
            )
            provider.address = p.address
            provider.website = p.website
            provider.notes = p.notes
            provider.isFavorite = p.isFavorite
            provider.rating = p.rating
            provider.home = home
            provider.homeIDString = home.id.uuidString
            context.insert(provider)
        }

        for proj in snapshot.projects {
            let project = RepairProject(
                title: proj.title,
                description: proj.projectDescription,
                category: proj.category,
                priority: proj.priority
            )
            project.status = proj.status
            project.notes = proj.notes
            project.home = home
            project.homeIDString = home.id.uuidString
            context.insert(project)
        }

        for (i, sec) in snapshot.documentSections.enumerated() {
            let section = DocumentSection(name: sec.name, sortOrder: i)
            section.home = home
            context.insert(section)

            for docSnap in sec.documents {
                let doc = HomeDocument(title: docSnap.title)
                doc.attachmentData = docSnap.attachmentData
                doc.attachmentName = docSnap.attachmentName
                doc.attachmentContentType = docSnap.attachmentContentType
                doc.section = section
                doc.home = home
                doc.homeIDString = home.id.uuidString
                context.insert(doc)
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
