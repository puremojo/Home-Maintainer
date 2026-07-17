//
//  ContentView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData
import CoreData
import UIKit

// Shared navigation state for cross-tab deep-links (e.g. "Take me to this appliance").
@Observable
final class NavigationCoordinator {
    var selectedTab: String = "tasks"
    var pendingAppliance: Appliance? = nil
    var pendingProject: RepairProject? = nil
    var pendingTask: MaintenanceTask? = nil
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService
    @Environment(HomeManager.self) private var homeManager
    @Environment(CloudSharingService.self) private var cloudSharingService
    @Query(sort: \Home.createdDate) private var homes: [Home]
    @State private var coordinator = NavigationCoordinator()
    @State private var shareAcceptErrorMessage: String?
    @AppStorage("frequencyEncodedMigrationDone") private var frequencyMigrationDone = false
    @AppStorage("homeIDStringMigrationDone") private var homeIDStringMigrationDone = false
    @AppStorage("sectionIDStringMigrationDone") private var sectionIDStringMigrationDone = false

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
            homeManager.restoreSelection(from: homes)
            // Run fixup if container is already available when view first appears.
            if cloudSharingService.persistentCloudKitContainer != nil {
                fixupFrequencyEncoded()
                fixupHomeIDStrings()
                fixupSectionIDStrings()
            }
        }
        .onChange(of: homes) { _, newHomes in
            if homeManager.currentHome == nil {
                homeManager.restoreSelection(from: newHomes)
            }
        }
        .onChange(of: cloudSharingService.sharedStoreIsReady) { _, isReady in
            if isReady {
                fixupOwnerNames()
                fixupFrequencyEncoded()
                fixupHomeIDStrings()
                fixupSectionIDStrings()
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

    /// On first launch after the multi-home update, create a default "My Home"
    /// and assign all existing records (which have home == nil) to it.
    private func migrateIfNeeded() {
        guard homes.isEmpty else { return }

        let defaultHome = Home(name: "My Home", ownerName: UIDevice.current.name, isLocallyCreated: true)
        modelContext.insert(defaultHome)

        // Filter in memory to avoid CloudKit-incompatible nil-relationship predicates.
        let homeIDStr = defaultHome.id.uuidString
        if let all = try? modelContext.fetch(FetchDescriptor<MaintenanceTask>()) {
            all.filter { $0.home == nil }.forEach {
                $0.home = defaultHome
                $0.homeIDString = homeIDStr
            }
        }
        if let all = try? modelContext.fetch(FetchDescriptor<Appliance>()) {
            all.filter { $0.home == nil }.forEach {
                $0.home = defaultHome
                $0.homeIDString = homeIDStr
            }
        }
        if let all = try? modelContext.fetch(FetchDescriptor<ServiceProvider>()) {
            all.filter { $0.home == nil }.forEach {
                $0.home = defaultHome
                $0.homeIDString = homeIDStr
            }
        }
        if let all = try? modelContext.fetch(FetchDescriptor<RepairProject>()) {
            all.filter { $0.home == nil }.forEach {
                $0.home = defaultHome
                $0.homeIDString = homeIDStr
            }
        }
        if let all = try? modelContext.fetch(FetchDescriptor<ChatConversation>()) {
            all.filter { $0.homeID == nil }.forEach { $0.homeID = defaultHome.id }
        }

        try? modelContext.save()
        homeManager.select(defaultHome)
    }

    /// One-time fixup for homes whose ownerName was set to the literal "Owner"
    /// by the old migrateIfNeeded() code. Runs only after the shared store is
    /// available so isCurrentUserOwner() can use the persistent-store check
    /// (rather than isLocallyCreated, which is unreliable for shared homes).
    private func fixupOwnerNames() {
        let deviceName = UIDevice.current.name
        var changed = false
        for home in homes where home.ownerName == "Owner" {
            guard homeManager.isCurrentUserOwner(of: home) else { continue }
            home.ownerName = deviceName
            changed = true
        }
        if changed { try? modelContext.save() }
    }

    /// One-time fixup that reads each task's stored Codable `frequency` via CoreData's
    /// NSManagedObject.value(forKey:) — which uses the registered value transformer and
    /// bypasses ModelContext.fulfill entirely — then writes the result into the new scalar
    /// `frequencyEncoded` attribute. Preserves all existing frequency data without requiring
    /// users to re-edit tasks. Safe for both private-store and shared-store objects.
    private func fixupFrequencyEncoded() {
        guard !frequencyMigrationDone,
              let container = cloudSharingService.persistentCloudKitContainer else { return }

        let ctx = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "MaintenanceTask")
        guard let tasks = try? ctx.fetch(request) else {
            frequencyMigrationDone = true
            return
        }

        var changed = false
        for task in tasks {
            guard let freq = task.value(forKey: "frequency") as? TaskFrequency else { continue }
            let encoded = freq.encoded
            if (task.value(forKey: "frequencyEncoded") as? String) != encoded {
                task.setValue(encoded, forKey: "frequencyEncoded")
                changed = true
            }
        }

        if changed { try? ctx.save() }
        frequencyMigrationDone = true
    }

    /// One-time backfill that reads each model's `home` relationship via CoreData's
    /// NSManagedObject.value(forKey:) — bypassing ModelContext.fulfill — then writes
    /// the home UUID into the new scalar `homeIDString` attribute. Also backfills
    /// `sourceProjectIDString` on MaintenanceTask. Skips shared-store objects
    /// (their home relationship may not be safely accessible).
    private func fixupHomeIDStrings() {
        guard !homeIDStringMigrationDone,
              let container = cloudSharingService.persistentCloudKitContainer else { return }

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
                // Skip shared-store objects — their home relationship may fault unsafely.
                if let sharedStore, obj.objectID.persistentStore === sharedStore { continue }
                if let existing = obj.value(forKey: key) as? String, !existing.isEmpty { continue }
                if let homeObj = obj.value(forKey: "home") as? NSManagedObject,
                   let homeID = homeObj.value(forKey: "id") as? UUID {
                    obj.setValue(homeID.uuidString, forKey: key)
                    changed = true
                }
            }
        }

        // Backfill sourceProjectIDString on MaintenanceTask
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

    /// One-time backfill that reads each HomeDocument's `section` relationship via CoreData
    /// and writes the section UUID into the new scalar `sectionIDString` attribute.
    /// Skips shared-store objects (their relationships may not be safely accessible).
    private func fixupSectionIDStrings() {
        guard !sectionIDStringMigrationDone,
              let container = cloudSharingService.persistentCloudKitContainer else { return }

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
    ContentView()
        .modelContainer(for: [
            Home.self,
            MaintenanceTask.self,
            MaintenanceRecord.self,
            Appliance.self,
            ServiceProvider.self,
            RepairProject.self,
            ProjectContact.self,
            Quote.self,
            Invoice.self,
            DocumentSection.self,
            HomeDocument.self
        ], inMemory: true)
        .environment(AuthService())
        .environment(HomeManager())
}
