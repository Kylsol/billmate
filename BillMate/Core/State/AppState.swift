//
//  AppState.swift
//  BillMate
//
//  Firestore model for homes/{homeId}/events/{eventId}
//  Used for audit logs and activity tracking.

import Combine
import Foundation
import FirebaseAuth


@MainActor
final class AppState: ObservableObject {
    @Published var authUser: AuthUser?
    @Published var activeHome: HomeDoc?
    @Published var activeRole: Role?

    func resetHomeSelection() {
        activeHome = nil
        activeRole = nil
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            // optional: log / surface error
            print("Firebase signOut failed:", error)
        }

        resetHomeSelection()
        authUser = nil
    }
}
