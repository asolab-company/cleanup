import SwiftUI

@main
struct CleanerApp: App {
    @UIApplicationDelegateAdaptor(AppsFlyerAppDelegate.self)
    private var appsFlyerAppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
