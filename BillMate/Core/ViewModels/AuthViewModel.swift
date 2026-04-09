import Combine
import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var name: String = ""

    @Published var errorMessage: String?
    @Published var isBusy: Bool = false

    private var handle: AuthStateDidChangeListenerHandle?

    func startListening(appState: AppState) {
        if handle != nil { return }

        handle = Auth.auth().addStateDidChangeListener { _, user in
            Task { @MainActor in
                if let user {
                    appState.authUser = AuthUser(
                        uid: user.uid,
                        email: user.email,
                        name: user.displayName
                    )
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

    func signInWithGoogle(appState: AppState) async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            let user = try await AuthService.signInWithGoogle()
            try await upsertUserDocument(for: user)
            appState.authUser = user
        } catch {
            errorMessage = error.localizedDescription
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

            if let user = AuthService.currentUser() {
                try await upsertUserDocument(for: user)
                appState.authUser = user
            } else {
                errorMessage = "Signed in, but no user was returned."
            }
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

            if let firebaseUser = Auth.auth().currentUser {
                let req = firebaseUser.createProfileChangeRequest()
                req.displayName = trimmedName
                try await req.commitChanges()
            }

            if let user = AuthService.currentUser() {
                try await upsertUserDocument(for: user)
                appState.authUser = user
            } else {
                errorMessage = "Account created, but no user was returned."
            }
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

    private func upsertUserDocument(for user: AuthUser) async throws {
        let trimmedName = (user.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = trimmedName.isEmpty
            ? ((user.email ?? "User").components(separatedBy: "@").first ?? "User")
            : trimmedName

        let data: [String: Any] = [
            "uid": user.uid,
            "email": user.email as Any,
            "name": safeName,
            "updatedAt": Timestamp(date: Date()),
            "createdAt": FieldValue.serverTimestamp()
        ]

        try await FirestoreService.userRef(user.uid).setData(data, merge: true)
    }
}
