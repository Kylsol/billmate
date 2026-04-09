import Foundation
import UIKit
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

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

    static func signInWithGoogle() async throws -> AuthUser {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw NSError(
                domain: "BillMate",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Missing Firebase client ID."]
            )
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard
            let scene = await UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let rootViewController = await scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            throw NSError(
                domain: "BillMate",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Could not find root view controller."]
            )
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

        guard let idToken = result.user.idToken?.tokenString else {
            throw NSError(
                domain: "BillMate",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Missing Google ID token."]
            )
        }

        let accessToken = result.user.accessToken.tokenString
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: accessToken
        )

        let authResult = try await Auth.auth().signIn(with: credential)
        let user = authResult.user

        return AuthUser(
            uid: user.uid,
            email: user.email,
            name: user.displayName
        )
    }

    static func signOut() throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
    }
}
