//
//  ContentView.swift
//  Home Maintainer
//

import SwiftUI
import CoreData
import UIKit

// Shared navigation state for cross-tab deep-links
@Observable
final class NavigationCoordinator {
    var selectedTab: String = "tasks"
    var pendingAppliance: Appliance? = nil
    var pendingProject: RepairProject? = nil
    var pendingTask: MaintenanceTask? = nil
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AuthService.self) private var authService
    @Environment(HomeManager.self) private var homeManager
    @Environment(CloudSharingService.self) private var cloudSharingService

    @FetchRequest(sortDescriptors: [SortDescriptor(\.createdDate)])
    private var homes: FetchedResults<Home>

    @State private var coordinator = NavigationCoordinator()
    @State private var shareAcceptErrorMessage: String?
    @AppStorage("homeIDStringMigrationDone") private var homeIDStringMigrationDone = false
    @AppStorage("sectionIDStringMigrationDone") private var sectionIDStringMigrationDone = false
    @AppStorage("debug_coredata_error") private var coreDataError: String = ""

    var body: some View {
        if !authService.isSignedIn {
            SignInView()
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        TabView(selection: Binding(
            get: { coordinator.selectedTab },
            set: { coordinator.selectedTab = $0 }
        )) {
            Tab("Tasks", systemImage: "checklist", value: "tasks") {
                MaintenanceTasksView()
            }
            Tab("Appliances", systemImage: "refrigerator", value: "appliances") {
                AppliancesView()
            }
            Tab("hAIndyman", systemImage: "wrench.and.screwdriver", value: "handyman") {
                HandymanView()
            }
            Tab("Projects", systemImage: "hammer", value: "projects") {
                RepairProjectsView()
            }
            Tab("More", systemImage: "ellipsis", value: "more") {
                MoreView()
            }
        }
        .environment(coordinator)
        .task {
            migrateIfNeeded()
            homeManager.restoreSelection(from: Array(homes))
            fixupOwnerNames()
            fixupHomeIDStrings()
            fixupSectionIDStrings()
        }
        .onChange(of: homes.count) { _, _ in
            if homeManager.currentHome == nil {
                homeManager.restoreSelection(from: Array(homes))
            }
        }
        .onChange(of: cloudSharingService.shareAcceptError) { _, message in
            shareAcceptErrorMessage = message
        }
        .alert("Invitation Error", isPresented: Binding(
            get: { shareAcceptErrorMessage != nil },
            set: { if !$0 { shareAcceptErrorMessage = nil; cloudSharingService.shareAcceptError = nil } }
        )) {
            Button("OK") { shareAcceptErrorMessage = nil; cloudSharingService.shareAcceptError = nil }
        } message: {
            Text(shareAcceptErrorMessage ?? "")
        }
        .alert("CoreData Error (Debug)", isPresented: Binding(
            get: { !coreDataError.isEmpty },
            set: { if !$0 { coreDataError = "" } }
        )) {
            Button("Clear") { coreDataError = "" }
        } message: {
            Text(coreDataError)
        }
        .sheet(
            isPresented: Binding(
                get: { homeManager.pendingImportURL != nil },
                set: { if !$0 { homeManager.pendingImportURL = nil } }
            )
        ) {
            if let url = homeManager.pendingImportURL {
                ImportHomeView(url: url)
            }
        }
    }

    /// On first launch, create a default "My Home" and assign all existing orphaned records to it.
    private func migrateIfNeeded() {
        guard homes.isEmpty else { return }

        let defaultHome = Home.make(name: "My Home", ownerName: UIDevice.current.name, isLocallyCreated: true, in: viewContext)
        let homeIDStr = defaultHome.id.uuidString

        for entityName in ["MaintenanceTask", "Appliance", "ServiceProvider", "RepairProject"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            if let objects = try? viewContext.fetch(request) {
                for obj in objects where obj.value(forKey: "home") == nil {
                    obj.setValue(defaultHome, forKey: "home")
                    obj.setValue(homeIDStr, forKey: "homeIDString")
                }
            }
        }

        let convRequest = NSFetchRequest<ChatConversation>(entityName: "ChatConversation")
        if let convs = try? viewContext.fetch(convRequest) {
            for conv in convs where conv.homeID == nil {
                conv.homeID = defaultHome.id
            }
        }

        try? viewContext.save()
        homeManager.select(defaultHome)
    }

    /// One-time fixup for homes whose ownerName was set to the literal "Owner".
    private func fixupOwnerNames() {
        let deviceName = UIDevice.current.name
        var changed = false
        for home in homes where home.ownerName == "Owner" {
            guard homeManager.isCurrentUserOwner(of: home) else { continue }
            home.ownerName = deviceName
            changed = true
        }
        if changed { try? viewContext.save() }
    }

    /// One-time backfill of scalar homeIDString attributes from relationships.
    private func fixupHomeIDStrings() {
        guard !homeIDStringMigrationDone else { return }
        guard let container = cloudSharingService.persistentCloudKitContainer else { return }

        let ctx = container.viewContext
        let sharedStore = cloudSharingService.sharedPersistentStore
        var changed = false

        let homeEntities = [
            ("MaintenanceTask",  "homeIDString"),
            ("Appliance",        "homeIDString"),
            ("ServiceProvider",  "homeIDString"),
            ("HomeDocument",     "homeIDString"),
            ("RepairProject",    "homeIDString"),
            ("DocumentSection",  "homeIDString"),
        ]

        for (entityName, key) in homeEntities {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            guard let objects = try? ctx.fetch(request) else { continue }
            for obj in objects {
                if let sharedStore, obj.objectID.persistentStore === sharedStore { continue }
                if let existing = obj.value(forKey: key) as? String, !existing.isEmpty { continue }
                if let homeObj = obj.value(forKey: "home") as? NSManagedObject,
                   let homeID = homeObj.value(forKey: "id") as? UUID {
                    obj.setValue(homeID.uuidString, forKey: key)
                    changed = true
                }
            }
        }

        let taskRequest = NSFetchRequest<NSManagedObject>(entityName: "MaintenanceTask")
        if let tasks = try? ctx.fetch(taskRequest) {
            for task in tasks {
                if let sharedStore, task.objectID.persistentStore === sharedStore { continue }
                if let existing = task.value(forKey: "sourceProjectIDString") as? String, !existing.isEmpty { continue }
                if let projObj = task.value(forKey: "sourceProject") as? NSManagedObject,
                   let projID = projObj.value(forKey: "id") as? UUID {
                    task.setValue(projID.uuidString, forKey: "sourceProjectIDString")
                    changed = true
                }
            }
        }

        if changed { try? ctx.save() }
        homeIDStringMigrationDone = true
    }

    /// One-time backfill of sectionIDString on HomeDocument from the section relationship.
    private func fixupSectionIDStrings() {
        guard !sectionIDStringMigrationDone else { return }
        guard let container = cloudSharingService.persistentCloudKitContainer else { return }

        let ctx = container.viewContext
        let sharedStore = cloudSharingService.sharedPersistentStore
        let request = NSFetchRequest<NSManagedObject>(entityName: "HomeDocument")
        guard let docs = try? ctx.fetch(request) else {
            sectionIDStringMigrationDone = true
            return
        }

        var changed = false
        for doc in docs {
            if let sharedStore, doc.objectID.persistentStore === sharedStore { continue }
            if let existing = doc.value(forKey: "sectionIDString") as? String, !existing.isEmpty { continue }
            if let sectionObj = doc.value(forKey: "section") as? NSManagedObject,
               let sectionID = sectionObj.value(forKey: "id") as? UUID {
                doc.setValue(sectionID.uuidString, forKey: "sectionIDString")
                changed = true
            }
        }

        if changed { try? ctx.save() }
        sectionIDStringMigrationDone = true
    }
}

#Preview {
    let model = AppDataModel.buildModel()
    let container = NSPersistentContainer(name: "Preview", managedObjectModel: model)
    let desc = NSPersistentStoreDescription()
    desc.type = NSInMemoryStoreType
    container.persistentStoreDescriptions = [desc]
    container.loadPersistentStores { _, _ in }
    return ContentView()
        .environment(\.managedObjectContext, container.viewContext)
        .environment(AuthService())
        .environment(HomeManager())
}
