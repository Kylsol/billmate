import Foundation
import FirebaseFirestore

/// Firestore model for homes/{homeId}
struct HomeDoc: Codable, Identifiable {

    // Firestore document id (homeId)
    @DocumentID var id: String?

    // Core fields
    var name: String
    var createdAt: Date
    var createdByUid: String

    // Soft delete / recycle bin fields
    // NOTE: Optional so older docs (without these fields) still decode safely.
    var isDeleted: Bool?
    var deletedAt: Date?
    var deleteExpiresAt: Date?
    var deletedByUid: String?
    var deletedByName: String?
}
