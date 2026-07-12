//
//  Home_MaintainerApp.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData

@main
struct Home_MaintainerApp: App {
    @State private var locationManager = LocationManager()
    @State private var businessSearchService = LocalBusinessSearchService()
    @State private var openAIService = OpenAIService()
    @State private var homeManager = HomeManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Home.self,
            MaintenanceTask.self,
            MaintenanceRecord.self,
            Appliance.self,
            AppliancePhoto.self,
            ServiceProvider.self,
            RepairProject.self,
            ProductLink.self,
            ProjectContact.self,
            Quote.self,
            Invoice.self,
            ChatConversation.self,
            ChatMessageData.self,
            ChatImageData.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // CloudKit unavailable (e.g. simulator without iCloud) — fall back to local-only store.
            let localConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(locationManager)
                .environment(businessSearchService)
                .environment(openAIService)
                .environment(homeManager)
                .onOpenURL { url in
                    homeManager.pendingImportURL = url
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
