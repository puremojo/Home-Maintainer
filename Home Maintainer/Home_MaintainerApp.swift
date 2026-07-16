//
//  Home_MaintainerApp.swift
//  Home Maintainer
//
//  Created by Michael Estrada on 11/11/24.
//

import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseAppCheck

@main
struct Home_MaintainerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var authService: AuthService
    @State private var locationManager = LocationManager()
    @State private var businessSearchService = LocalBusinessSearchService()
    @State private var geminiService: GeminiService
    @State private var subscriptionService: SubscriptionService
    @State private var homeManager = HomeManager()
    @State private var cloudSharingService: CloudSharingService

    init() {
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
        #endif
        FirebaseApp.configure()
        _authService = State(initialValue: AuthService())
        _geminiService = State(initialValue: GeminiService())
        _subscriptionService = State(initialValue: SubscriptionService())

        let sharingService = CloudSharingService()
        _cloudSharingService = State(initialValue: sharingService)
        CloudSharingService.shared = sharingService
    }

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
            ChatImageData.self,
            DocumentSection.self,
            HomeDocument.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.EstraDOS.Home-Maintainer")
        )

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: HomeMigrationPlan.self,
                configurations: [modelConfiguration]
            )
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
                .environment(authService)
                .environment(locationManager)
                .environment(businessSearchService)
                .environment(geminiService)
                .environment(subscriptionService)
                .environment(homeManager)
                .environment(cloudSharingService)
                .onOpenURL { url in
                    homeManager.pendingImportURL = url
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - AppDelegate (routes scene connections to SceneDelegate for CloudKit share acceptance)

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}
