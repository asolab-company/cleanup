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

    private enum Event {
        static let subscription = "af_app_subscription"
        static let webViewSubscriptionSuccess =
            "af_webview_subscription_success"
        static let source = "cleaner_ios_app"
        static let context = "subscription_purchase_success"
        static let webViewSource = "cleaner_ios_webview"
        static let webViewContext = "webview_checkout_success"
    }

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
            "product_id": productID,
            "event_source": Event.source,
            "event_context": Event.context
        ]
        AppsFlyerLib.shared().logEvent(
            Event.subscription,
            withValues: values
        )
        #endif
    }

    func trackWebViewSubscriptionSuccess() {
        #if canImport(AppsFlyerLib)
        let values: [AnyHashable: Any] = [
            "event_source": Event.webViewSource,
            "event_context": Event.webViewContext,
            "purchase_channel": "webview"
        ]
        AppsFlyerLib.shared().logEvent(
            Event.webViewSubscriptionSuccess,
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
