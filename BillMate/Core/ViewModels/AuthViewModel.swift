import Combine
import Foundation
import FirebaseAuth

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var name: String = ""          // ✅ add this

    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    private var handle: AuthStateDidChangeListenerHandle?

    func startListening(appState: AppState) {
        if handle != nil { return }
        handle = Auth.auth().addStateDidChangeListener { _, user in
            Task { @MainActor in
                if let user {
                    appState.authUser = AuthUser(uid: user.uid, email: user.email, name: user.displayName)
                } else {
                    appState.authUser = nil
                    appState.resetHomeSelection()
                }
            }
        }
    }

    func stopListening() {
        if let h = handle {
            Auth.auth().removeStateDidChangeListener(h)
            handle = nil
        }
    }

    func signIn(appState: AppState) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            try await AuthService.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            appState.authUser = AuthService.currentUser()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createAccount(appState: AppState) async {
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required."
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            try await AuthService.createAccount(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )

            // ✅ store display name on FirebaseAuth user (easy + useful)
            if let user = Auth.auth().currentUser {
                let req = user.createProfileChangeRequest()
                req.displayName = trimmedName
                try await req.commitChanges()
            }

            appState.authUser = AuthService.currentUser()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut(appState: AppState) {
        errorMessage = nil
        do {
            try AuthService.signOut()
            appState.authUser = nil
            appState.resetHomeSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
