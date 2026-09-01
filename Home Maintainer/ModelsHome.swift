//
//  ModelsHome.swift
//  Home Maintainer
//

import Foundation
import CoreData

@objc(Home)
public final class Home: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var address: String
    @NSManaged public var createdDate: Date
    @NSManaged public var ownerName: String
    @NSManaged public var isLocallyCreated: Bool

    // Relationships (NSSet for Core Data; typed accessors below)
    @NSManaged public var tasks: NSSet?
    @NSManaged public var appliances: NSSet?
    @NSManaged public var serviceProviders: NSSet?
    @NSManaged public var projects: NSSet?
    @NSManaged public var documentSections: NSSet?
    @NSManaged public var homeDocuments: NSSet?

    // MARK: - Typed relationship helpers

    public var taskArray: [MaintenanceTask] {
        (tasks as? Set<MaintenanceTask>)?.sorted { $0.createdAt < $1.createdAt } ?? []
    }

    public var applianceArray: [Appliance] {
        (appliances as? Set<Appliance>)?.sorted { $0.name < $1.name } ?? []
    }

    public var documentSectionArray: [DocumentSection] {
        (documentSections as? Set<DocumentSection>)?.sorted { $0.sortOrder < $1.sortOrder } ?? []
    }

    // MARK: - Convenience factory

    @discardableResult
    static func make(
        name: String,
        ownerName: String = "",
        address: String = "",
        isLocallyCreated: Bool = true,
        in context: NSManagedObjectContext
    ) -> Home {
        let home = Home(context: context)
        home.id = UUID()
        home.name = name
        home.ownerName = ownerName
        home.address = address
        home.isLocallyCreated = isLocallyCreated
        home.createdDate = Date()
        return home
    }
}
