import Foundation
import FirebaseAuth

struct AuthUser {
    let uid: String
    let email: String?
    let name: String?
}

enum AuthService {
    static func currentUser() -> AuthUser? {
        guard let u = Auth.auth().currentUser else { return nil }
        return AuthUser(
            uid: u.uid,
            email: u.email,
            name: u.displayName
        )
    }

    static func signIn(email: String, password: String) async throws {
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
    }

    static func createAccount(email: String, password: String) async throws {
        _ = try await Auth.auth().createUser(withEmail: email, password: password)
    }

    static func signOut() throws {
        try Auth.auth().signOut()
    }
}
