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
    // true when this home was created on this device; false when imported from someone else.
    // Used to show "You (Owner)" vs the stored owner name without needing CloudKit entitlements.
    var isLocallyCreated: Bool

    @Relationship(deleteRule: .cascade, inverse: \MaintenanceTask.home)
    var tasks: [MaintenanceTask]?

    @Relationship(deleteRule: .cascade, inverse: \Appliance.home)
    var appliances: [Appliance]?

    @Relationship(deleteRule: .cascade, inverse: \ServiceProvider.home)
    var serviceProviders: [ServiceProvider]?

    @Relationship(deleteRule: .cascade, inverse: \RepairProject.home)
    var projects: [RepairProject]?

    @Relationship(deleteRule: .cascade, inverse: \ChatConversation.home)
    var chatConversations: [ChatConversation]?

    init(name: String, address: String = "", ownerName: String = "", isLocallyCreated: Bool = true) {
        self.id = UUID()
        self.name = name
        self.address = address
        self.createdDate = Date()
        self.ownerName = ownerName
        self.isLocallyCreated = isLocallyCreated
    }
}
