//
//  ContentView.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

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
    @Query(sort: \Home.createdDate) private var homes: [Home]
    @State private var coordinator = NavigationCoordinator()

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
            Invoice.self,
            DocumentSection.self,
            HomeDocument.self
        ], inMemory: true)
        .environment(AuthService())
        .environment(HomeManager())
}
