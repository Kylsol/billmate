import Foundation
import FirebaseFirestore

/// Firestore model for homes/{homeId}/invites/{code}
struct InviteDoc: Identifiable, Codable {

    // Firestore document ID (commonly the invite code itself)
    @DocumentID var id: String?

    // Which home this invite belongs to
    var homeId: String

    // Who created the invite (uid)
    var createdByUid: String

    // When this invite expires
    var expiresAt: Date

    // Usage limits
    var maxUses: Int
    var uses: Int

    // Audit timestamp
    var createdAt: Date

    // Required so you can collectionGroup query invites by a field
    // (Firestore can't query by documentId across collectionGroup reliably the way you want)
    var code: String
}
