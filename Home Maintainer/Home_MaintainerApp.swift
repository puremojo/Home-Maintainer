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

        let container = CloudSharingService.makeContainer()
        let sharingService = CloudSharingService(container: container)
        _cloudSharingService = State(initialValue: sharingService)
        CloudSharingService.shared = sharingService
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
                .task {
                    await cloudSharingService.performInitialUploadIfNeeded()
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
        Task {
            await CloudSharingService.shared?.handleRemoteNotification()
            completionHandler(.newData)
        }
    }
}
