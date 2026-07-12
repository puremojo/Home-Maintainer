//
//  ContentView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HomeManager.self) private var homeManager
    @Query(sort: \Home.createdDate) private var homes: [Home]

    var body: some View {
        TabView {
            Tab("Tasks", systemImage: "checklist") {
                MaintenanceTasksView()
            }
            Tab("Appliances", systemImage: "refrigerator") {
                AppliancesView()
            }
            Tab("Providers", systemImage: "person.2") {
                ServiceProvidersView()
            }
            Tab("Projects", systemImage: "hammer") {
                RepairProjectsView()
            }
            Tab("hAIndyman", systemImage: "wrench.and.screwdriver") {
                HandymanView()
            }
        }
        .task {
            migrateIfNeeded()
            homeManager.restoreSelection(from: homes)
        }
        .onChange(of: homes) { _, newHomes in
            if homeManager.currentHome == nil {
                homeManager.restoreSelection(from: newHomes)
            }
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

        let defaultHome = Home(name: "My Home", ownerName: "Owner", isLocallyCreated: true)
        modelContext.insert(defaultHome)

        // Filter in memory to avoid CloudKit-incompatible nil-relationship predicates.
        if let all = try? modelContext.fetch(FetchDescriptor<MaintenanceTask>()) {
            all.filter { $0.home == nil }.forEach { $0.home = defaultHome }
        }
        if let all = try? modelContext.fetch(FetchDescriptor<Appliance>()) {
            all.filter { $0.home == nil }.forEach { $0.home = defaultHome }
        }
        if let all = try? modelContext.fetch(FetchDescriptor<ServiceProvider>()) {
            all.filter { $0.home == nil }.forEach { $0.home = defaultHome }
        }
        if let all = try? modelContext.fetch(FetchDescriptor<RepairProject>()) {
            all.filter { $0.home == nil }.forEach { $0.home = defaultHome }
        }
        if let all = try? modelContext.fetch(FetchDescriptor<ChatConversation>()) {
            all.filter { $0.home == nil }.forEach { $0.home = defaultHome }
        }

        try? modelContext.save()
        homeManager.select(defaultHome)
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
            Invoice.self
        ], inMemory: true)
        .environment(HomeManager())
}
