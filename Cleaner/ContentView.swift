import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding =
        false
    @State private var showOnboarding = false
    @State private var appUnlocked = false

    var body: some View {
        Group {
            if appUnlocked {
                MainView()
            } else if showOnboarding {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        hasCompletedOnboarding = true
                        appUnlocked = true
                    }
                }
            } else {
                LoadingView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if hasCompletedOnboarding {
                            appUnlocked = true
                        } else {
                            showOnboarding = true
                        }
                    }
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
