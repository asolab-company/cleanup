import Foundation
import AppTrackingTransparency
import UIKit

#if canImport(AppsFlyerLib)
import AppsFlyerLib
#endif

enum AppsFlyerConfig {
    static let devKey = "cSRFayvDVGvzuDdmHNu9BZ"
    static let appID = "6760419354"
}

final class AppsFlyerService {
    static let shared = AppsFlyerService()

    private var isConfigured = false
    private var didStartAppsFlyer = false
    private var attRequestAttempts = 0
    private let maxATTRequestAttempts = 3

    private init() {}

    func configure() {
        #if canImport(AppsFlyerLib)
        guard !isConfigured else { return }
        let appsFlyer = AppsFlyerLib.shared()
        appsFlyer.appsFlyerDevKey = AppsFlyerConfig.devKey
        appsFlyer.appleAppID = AppsFlyerConfig.appID
        appsFlyer.waitForATTUserAuthorization(timeoutInterval: 60)
        appsFlyer.isDebug = false
        isConfigured = true
        #endif
    }

    func startRespectingTrackingAuthorization() {
        if didStartAppsFlyer {
            return
        }

        if #available(iOS 14, *) {
            let status = ATTrackingManager.trackingAuthorizationStatus

            if status == .notDetermined {
                requestATTAuthorizationAndStart()
                return
            }
        }

        startAppsFlyer()
    }

    @available(iOS 14, *)
    private func requestATTAuthorizationAndStart() {
        guard attRequestAttempts < maxATTRequestAttempts else {
            startAppsFlyer()
            return
        }

        attRequestAttempts += 1
        let currentAttempt = attRequestAttempts

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard UIApplication.shared.applicationState == .active else {
                return
            }

            ATTrackingManager.requestTrackingAuthorization { result in
                DispatchQueue.main.async {
                    if result == .notDetermined && currentAttempt < self.maxATTRequestAttempts {
                        self.requestATTAuthorizationAndStart()
                    } else {
                        self.startAppsFlyer()
                    }
                }
            }
        }
    }

    private func startAppsFlyer() {
        #if canImport(AppsFlyerLib)
        guard !didStartAppsFlyer else {
            return
        }
        if !isConfigured {
            configure()
        }
        let appsFlyer = AppsFlyerLib.shared()
        appsFlyer.isDebug = false
        appsFlyer.start()
        didStartAppsFlyer = true
        #endif
    }

    func handleOpen(url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) {
        #if canImport(AppsFlyerLib)
        AppsFlyerLib.shared().handleOpen(url, options: options)
        #endif
    }

    func trackSubscription(productID: String) {
        #if canImport(AppsFlyerLib)
        let values: [AnyHashable: Any] = [
            "product_id": productID
        ]
        AppsFlyerLib.shared().logEvent(
            "af_app_subscription",
            withValues: values
        )
        #endif
    }

}

final class AppsFlyerAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppsFlyerService.shared.configure()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        AppsFlyerService.shared.startRespectingTrackingAuthorization()
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        AppsFlyerService.shared.handleOpen(url: url, options: options)
        return true
    }

}
