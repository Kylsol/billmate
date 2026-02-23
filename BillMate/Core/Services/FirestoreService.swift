import Foundation
import FirebaseFirestore

enum FirestoreService {
    static let db = Firestore.firestore()

    // MARK: - Paths
    static func homeRef(_ homeId: String) -> DocumentReference {
        db.collection("homes").document(homeId)
    }

    static func membersCol(_ homeId: String) -> CollectionReference {
        homeRef(homeId).collection("members")
    }

    static func billsCol(_ homeId: String) -> CollectionReference {
        homeRef(homeId).collection("bills")
    }

    static func paymentsCol(_ homeId: String) -> CollectionReference {
        homeRef(homeId).collection("payments")
    }

    static func eventsCol(_ homeId: String) -> CollectionReference {
        homeRef(homeId).collection("events")
    }

    static func invitesCol(_ homeId: String) -> CollectionReference {
        homeRef(homeId).collection("invites")
    }

    static func inviteRef(homeId: String, code: String) -> DocumentReference {
        invitesCol(homeId).document(code)
    }
    
    static func userRef(_ uid: String) -> DocumentReference {
        db.collection("users").document(uid)
    }

    // MARK: - Async Helpers (no FirestoreSwift required)

    static func setEncodable<T: Encodable>(
        _ value: T,
        to ref: DocumentReference,
        merge: Bool = false
    ) async throws {
        let data = try encodeToFirestore(value)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ref.setData(data, merge: merge) { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: ())
                }
            }
        }
    }

    static func update(
        _ data: [String: Any],
        on ref: DocumentReference
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ref.updateData(data) { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: ())
                }
            }
        }
    }

    static func delete(
        _ ref: DocumentReference
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ref.delete { error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: ())
                }
            }
        }
    }

    // MARK: - Encoding

    /// Converts an Encodable into a Firestore `[String: Any]` using JSON.
    /// Dates are encoded as milliseconds since 1970.
    private static func encodeToFirestore<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970

        let jsonData = try encoder.encode(value)
        let obj = try JSONSerialization.jsonObject(with: jsonData, options: [])

        guard let dict = obj as? [String: Any] else {
            throw NSError(
                domain: "BillMate",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to encode object into Firestore dictionary."]
            )
        }
        return dict
    }
}
