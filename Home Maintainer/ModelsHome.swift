//
//  ModelsHome.swift
//  Home Maintainer
//

import Foundation
import SwiftData

@Model
final class Home {
    var id: UUID
    var name: String
    var address: String
    var createdDate: Date
    var ownerName: String
    var isLocallyCreated: Bool

    @Relationship(deleteRule: .cascade, inverse: \MaintenanceTask.home)
    var tasks: [MaintenanceTask]?

    @Relationship(deleteRule: .cascade, inverse: \Appliance.home)
    var appliances: [Appliance]?

    @Relationship(deleteRule: .cascade, inverse: \ServiceProvider.home)
    var serviceProviders: [ServiceProvider]?

    @Relationship(deleteRule: .cascade, inverse: \RepairProject.home)
    var projects: [RepairProject]?

    // chatConversations removed: ChatConversation now stores homeID: UUID? instead of
    // a SwiftData relationship, keeping chat outside the CloudKit zone share for a Home.

    @Relationship(deleteRule: .cascade, inverse: \DocumentSection.home)
    var documentSections: [DocumentSection]?

    @Relationship(deleteRule: .cascade, inverse: \HomeDocument.home)
    var homeDocuments: [HomeDocument]?

    init(name: String, address: String = "", ownerName: String = "", isLocallyCreated: Bool = true) {
        self.id = UUID()
        self.name = name
        self.address = address
        self.createdDate = Date()
        self.ownerName = ownerName
        self.isLocallyCreated = isLocallyCreated
    }
}
