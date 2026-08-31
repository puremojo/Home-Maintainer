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

    // Stored without a default value so it can be initialized in init() after
    // CloudSharingService registers its notification observer. This ensures the
    // NSPersistentCloudKitContainer.eventChangedNotification is never missed.
    let sharedModelContainer: ModelContainer

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

        // Register the CloudSharingService observer BEFORE creating the ModelContainer,
        // so the eventChangedNotification is captured even when CloudKit is already warm.
        let sharingService = CloudSharingService()
        _cloudSharingService = State(initialValue: sharingService)
        CloudSharingService.shared = sharingService

        sharedModelContainer = Self.makeModelContainer()
    }

    private static func makeModelContainer() -> ModelContainer {
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
    }

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
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register with APNS so CloudKit can deliver silent push notifications to this device.
        // Without this call, NSPersistentCloudKitContainer never receives a device token and
        // falls back to periodic polling (~30 min) instead of near-instant push-driven sync.
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }

    // Without this handler, iOS has no signal to grant the app background time when
    // CloudKit sends a silent push saying shared-zone data has changed. NSPersistentCloudKitContainer
    // handles the actual fetch internally; we just need to acknowledge the notification so iOS
    // gives the container enough time to complete the import.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        completionHandler(.newData)
    }
}
