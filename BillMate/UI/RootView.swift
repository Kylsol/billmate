import Combine
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var authVM = AuthViewModel()

    var body: some View {
        Group {
            if appState.authUser == nil {
                LoginView()
                    .environmentObject(appState)
                    .environmentObject(authVM)
            } else if appState.activeHome == nil {
                HomeListView()
                    .environmentObject(appState)
            } else {
                DashboardView()
                    .environmentObject(appState)
            }
        }
        .onAppear {
            authVM.startListening(appState: appState)
        }
    }
}
