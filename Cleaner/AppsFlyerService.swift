import Foundation
import AppTrackingTransparency
import UIKit
import os

#if canImport(AppsFlyerLib)
import AppsFlyerLib
#endif

enum AppsFlyerConfig {
    static let devKey = "cSRFayvDVGvzuDdmHNu9BZ"
    static let appID = "6760419354"
}

final class AppsFlyerService {
    static let shared = AppsFlyerService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cleaner",
        category: "AppsFlyer"
    )
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
        logger.info("AppsFlyer debug flag configured: \(appsFlyer.isDebug, privacy: .public)")
        isConfigured = true
        #endif
    }

    func startRespectingTrackingAuthorization() {
        if didStartAppsFlyer {
            return
        }

        if #available(iOS 14, *) {
            let status = ATTrackingManager.trackingAuthorizationStatus
            logger.info(
                "ATT status before request: \(self.statusText(status), privacy: .public)"
            )

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
            logger.info("ATT request attempts exhausted, starting AppsFlyer without ATT prompt")
            startAppsFlyer()
            return
        }

        attRequestAttempts += 1
        let currentAttempt = attRequestAttempts

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard UIApplication.shared.applicationState == .active else {
                self.logger.info("ATT request skipped because app is not active, attempt=\(currentAttempt, privacy: .public)")
                return
            }

            ATTrackingManager.requestTrackingAuthorization { result in
                self.logger.info(
                    "ATT request result: \(self.statusText(result), privacy: .public), attempt=\(currentAttempt, privacy: .public)"
                )
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
        logger.info("AppsFlyer debug flag before start: \(appsFlyer.isDebug, privacy: .public)")
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
        logger.info(
            "AppsFlyer event sent: af_app_subscription, product_id=\(productID, privacy: .public)"
        )
        #else
        logger.info(
            "AppsFlyer SDK unavailable, skipped event: af_app_subscription, product_id=\(productID, privacy: .public)"
        )
        #endif
    }

    @available(iOS 14, *)
    private func statusText(
        _ status: ATTrackingManager.AuthorizationStatus
    ) -> String {
        switch status {
        case .notDetermined:
            return "notDetermined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        @unknown default:
            return "unknown"
        }
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
