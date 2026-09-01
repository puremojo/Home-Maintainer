//
//  Home_MaintainerApp.swift
//  Home Maintainer
//

import SwiftUI
import CoreData
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

        // Create the container FIRST so it can be injected into CloudSharingService.
        // Both private and shared stores are configured at init time, which causes
        // NSPersistentCloudKitContainer to register push-driven CloudKit subscriptions
        // for BOTH stores — eliminating the 30-minute polling fallback.
        let container = Self.makePersistentCloudKitContainer()
        let sharingService = CloudSharingService(container: container)
        _cloudSharingService = State(initialValue: sharingService)
        CloudSharingService.shared = sharingService
    }

    static func makePersistentCloudKitContainer() -> NSPersistentCloudKitContainer {
        let model = AppDataModel.buildModel()
        let container = NSPersistentCloudKitContainer(name: "HomeMaintainer", managedObjectModel: model)

        let baseURL = NSPersistentContainer.defaultDirectoryURL()
        let privateURL = baseURL.appendingPathComponent("HomeMaintainer.sqlite")
        let sharedURL  = baseURL.appendingPathComponent("HomeMaintainerShared.sqlite")

        // Pre-flight: probe each store file with the current model.
        // If the file exists but is incompatible (e.g., leftover from an earlier schema),
        // destroy it so loadPersistentStores creates a fresh empty store.
        for url in [privateURL, sharedURL] where FileManager.default.fileExists(atPath: url.path) {
            let probe = NSPersistentStoreCoordinator(managedObjectModel: model)
            let opts: [AnyHashable: Any] = [NSReadOnlyPersistentStoreOption: true]
            if (try? probe.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil,
                                              at: url, options: opts)) == nil {
                NSLog("⚠️ Destroying incompatible CoreData store: \(url.lastPathComponent)")
                try? probe.destroyPersistentStore(at: url, ofType: NSSQLiteStoreType, options: nil)
            }
        }

        let privateDesc = NSPersistentStoreDescription(url: privateURL)
        // NSPersistentCloudKitContainer requires persistent history and remote-change notifications.
        // Set them explicitly — some OS versions don't add them automatically.
        privateDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateDesc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        let privateOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.EstraDOS.Home-Maintainer")
        privateOptions.databaseScope = .private
        privateDesc.cloudKitContainerOptions = privateOptions

        let sharedDesc = NSPersistentStoreDescription(url: sharedURL)
        sharedDesc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        sharedDesc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        let sharedOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.EstraDOS.Home-Maintainer")
        sharedOptions.databaseScope = .shared
        sharedDesc.cloudKitContainerOptions = sharedOptions

        container.persistentStoreDescriptions = [privateDesc, sharedDesc]

        // Clear any previous load error; will be re-set below if loading fails.
        UserDefaults.standard.removeObject(forKey: "debug_coredata_error")

        container.loadPersistentStores { description, error in
            if let error {
                let storeName = description.url?.lastPathComponent ?? "unknown"
                let msg = "'\(storeName)': \(error as NSError)"
                NSLog("❌ CoreData load error — \(msg)")
                // Persist so ContentView can surface it on next launch via an alert.
                UserDefaults.standard.set(msg, forKey: "debug_coredata_error")
                UserDefaults.standard.synchronize()
                // Do NOT fatalError — let the app start in degraded mode so the
                // error alert is visible rather than another silent EXC_BREAKPOINT crash.
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return container
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
                .environment(\.managedObjectContext, cloudSharingService.viewContext)
                .onOpenURL { url in
                    homeManager.pendingImportURL = url
                }
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register with APNS so CloudKit can deliver silent push notifications to this device.
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

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        completionHandler(.newData)
    }
}
