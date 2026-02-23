import SwiftUI
import FirebaseCore

@main
struct BillMateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var appState = AppState()
    @StateObject private var homesVM = HomesViewModel()
    @StateObject private var authVM = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(homesVM)
                .environmentObject(authVM)
        }
    }
}
